//
//  AgencyAlertsStoreConcurrencyTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Regression coverage for the `stateLock` on `AgencyAlertsStore`.
///
/// The store's mutable state (`agencies`, `alerts`, `readAlertIDs`, and the mirrored
/// `readAgencyAlertIDs` UserDefaults key) is touched from several contexts at once:
/// `update()` from a background `Task`, `markAlertRead`/UI reads from `@MainActor`,
/// and `deleteAgencyAlerts` from the store's serial queue. Removing the lock or
/// hoisting a mutation out of its critical section should surface here under Thread
/// Sanitizer (preferred CI run) — and without TSan, an unhandled race typically
/// still manifests as a crash or a count mismatch when the fanout is wide enough.
@Suite(.serialized)
final class AgencyAlertsStoreConcurrencyTests: OBATestCase {
    var queue: OperationQueue!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    // MARK: - Helpers

    private func createApplication(dataLoader: MockDataLoader) -> Application {
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        let locManager = MockAuthorizedLocationManager(
            updateLocation: TestData.mockSeattleLocation,
            updateHeading: TestData.mockHeading
        )
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        locationService.startUpdates()

        let config = AppConfig(
            regionsBaseURL: regionsURL,
            apiKey: apiKey,
            appVersion: appVersion,
            userDefaults: userDefaults,
            analytics: AnalyticsMock(),
            queue: queue,
            locationService: locationService,
            bundledRegionsFilePath: bundledRegionsPath,
            regionsAPIPath: regionsAPIPath,
            dataLoader: dataLoader,
            fixedRegionName: Fixtures.pugetSoundRegion.name
        )
        return Application(config: config)
    }

    /// Builds N high-severity alerts whose active period starts "now" so they pass
    /// the 8-hour recency filter exercised by `recentHighSeverityAlerts`.
    private func makeRecentHighSeverityAlerts(count: Int) throws -> [AgencyAlert] {
        let agencies = try Fixtures.loadRESTAPIPayload(type: [AgencyWithCoverage].self, fileName: "agencies_with_coverage.json")
        let agency = try #require(agencies.first)

        var period = TransitRealtime_TimeRange()
        period.start = UInt64(Date().timeIntervalSince1970)

        var entitySelector = TransitRealtime_EntitySelector()
        entitySelector.agencyID = agency.agencyID

        var transitAlert = TransitRealtime_Alert()
        transitAlert.severityLevel = .warning
        transitAlert.informedEntity = [entitySelector]
        transitAlert.activePeriod = [period]

        return try (0..<count).map { index in
            var feedEntity = TransitRealtime_FeedEntity()
            feedEntity.id = "concurrency-test-alert-\(index)"
            feedEntity.alert = transitAlert
            return try AgencyAlert(feedEntity: feedEntity, agency: agency)
        }
    }

    // MARK: - Fanout

    /// Spins up concurrent reads and writes that all funnel through `stateLock`:
    /// `markAlertRead`, `isAlertUnread`, `recentHighSeverityAlerts`, and `agencyAlerts`.
    /// If the lock is missing or held inconsistently, TSan will flag the data race;
    /// without TSan, a corrupted `Set<AgencyAlert>` typically crashes the run.
    @Test @MainActor
    func `Concurrent reads and writes do not crash or corrupt state`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let store = app.alertsStore

        let alerts = try makeRecentHighSeverityAlerts(count: 25)
        store.insertAlerts(alerts)

        // Sanity baseline before the fanout: every seeded alert is present and unread.
        #expect(store.recentHighSeverityAlerts.count == alerts.count)
        #expect(store.recentUnreadHighSeverityAlerts.count == alerts.count)

        // 25 alerts × 4 task groups × ~25 inner iterations is wide enough that an
        // unsynchronized read of `alerts`/`readAlertIDs` races on a real CPU.
        let iterations = 25
        await withTaskGroup(of: Void.self) { group in
            for alert in alerts {
                group.addTask {
                    for _ in 0..<iterations {
                        store.markAlertRead(alert)
                    }
                }
                group.addTask {
                    for _ in 0..<iterations {
                        _ = store.isAlertUnread(alert)
                    }
                }
            }
            group.addTask {
                for _ in 0..<iterations {
                    _ = store.recentHighSeverityAlerts
                }
            }
            group.addTask {
                for _ in 0..<iterations {
                    _ = store.agencyAlerts
                }
            }
        }

        // After the fanout, every alert must be marked read exactly once (idempotent
        // inserts into a `Set`), and the alert set itself must be intact.
        #expect(store.recentHighSeverityAlerts.count == alerts.count)
        #expect(store.recentUnreadHighSeverityAlerts.isEmpty)
        for alert in alerts {
            #expect(!store.isAlertUnread(alert))
        }
    }

    /// #1145: `deleteAgencyAlerts()`'s `removeAll()` is the mutation most likely to
    /// corrupt state during a concurrent read. Region change drives that path;
    /// fan it out against reads so a missing lock fails without relying on TSan.
    @Test @MainActor
    func `Concurrent delete-via-region-change and reads do not corrupt state`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let store = app.alertsStore

        let alerts = try makeRecentHighSeverityAlerts(count: 20)
        store.insertAlerts(alerts)
        #expect(store.recentHighSeverityAlerts.count == alerts.count)

        let iterations = 30
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                for _ in 0..<iterations {
                    // `regionsService(_:updatedRegion:)` → `deleteAgencyAlerts()` on the
                    // store's serial queue. Re-seed after each wipe so the next delete
                    // still has something to clear.
                    store.insertAlerts(alerts)
                    store.regionsService(app.regionsService, updatedRegion: Fixtures.tampaRegion)
                }
            }
            group.addTask {
                for _ in 0..<iterations {
                    _ = store.recentHighSeverityAlerts
                    _ = store.agencyAlerts
                    for alert in alerts {
                        _ = store.isAlertUnread(alert)
                    }
                }
            }
            group.addTask {
                for _ in 0..<iterations {
                    for alert in alerts {
                        store.markAlertRead(alert)
                    }
                }
            }
        }

        // Wait for the serial delete queue + any in-flight `checkForUpdates`
        // kicked off by `updatedRegion` to settle.
        try await Task.sleep(nanoseconds: 300_000_000)

        // `updatedRegion` deletes then refetches — do not assert emptiness.
        // Coherence under the lock: recent/unread subsets stay inside `agencyAlerts`,
        // and a final mark-all-read leaves no unread high-severity rows.
        let allIDs = Set(store.agencyAlerts.map(\.id))
        let recentIDs = Set(store.recentHighSeverityAlerts.map(\.id))
        #expect(recentIDs.isSubset(of: allIDs))
        for alert in store.agencyAlerts {
            store.markAlertRead(alert)
        }
        #expect(store.recentUnreadHighSeverityAlerts.isEmpty)
    }
}
