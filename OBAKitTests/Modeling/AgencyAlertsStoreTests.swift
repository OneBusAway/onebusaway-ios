//
//  AgencyAlertsStoreTests.swift
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

/// Hears how a `checkForUpdates()` call ended. The store reports through its
/// delegates from an unstructured task, so the test waits on the callback.
@MainActor
private final class AlertsOutcomeDelegate: NSObject, AgencyAlertsDelegate {
    enum Outcome {
        case updated
        case failed(Error)
    }

    private var continuation: CheckedContinuation<Outcome, Never>?

    func wait(for action: () -> Void) async -> Outcome {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            action()
        }
    }

    func agencyAlertsUpdated() {
        continuation?.resume(returning: .updated)
        continuation = nil
    }

    func agencyAlertsStore(_ store: AgencyAlertsStore, displayError error: Error) {
        continuation?.resume(returning: .failed(error))
        continuation = nil
    }
}

@Suite(.serialized, .timeLimit(.minutes(1)))
final class AgencyAlertsStoreTests: OBATestCase {
    private var dataLoader: MockDataLoader!
    private var regionsService: RegionsService!
    private var store: AgencyAlertsStore!
    private var outcomeDelegate: AlertsOutcomeDelegate!

    override init() async throws {
        try await super.init()

        dataLoader = MockDataLoader(testName: name)
        regionsService = RegionsService(
            apiService: nil,
            locationService: LocationService(userDefaults: userDefaults, locationManager: LocationManagerMock()),
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: nil,
            fileStorage: MockRegionsFileStorage()
        )
        store = AgencyAlertsStore(userDefaults: userDefaults, regionsService: regionsService)
        store.apiService = buildRESTService(dataLoader: dataLoader)
        store.obacoService = buildObacoService(dataLoader: dataLoader)

        outcomeDelegate = AlertsOutcomeDelegate()
        store.addDelegate(outcomeDelegate)
    }

    private func checkForUpdates() async -> AlertsOutcomeDelegate.Outcome {
        await outcomeDelegate.wait { store.checkForUpdates() }
    }

    // MARK: - Stubs

    /// A feed holding an agency-wide alert for King County Metro (agency `1`)
    /// with each of `alertIDs`.
    private func feed(alertIDs: [String]) throws -> Data {
        var selector = TransitRealtime_EntitySelector()
        selector.agencyID = "1"

        var message = TransitRealtime_FeedMessage()
        message.header.gtfsRealtimeVersion = "2.0"
        message.entity = alertIDs.map { alertID in
            var entity = TransitRealtime_FeedEntity()
            entity.id = alertID
            entity.alert.informedEntity = [selector]
            return entity
        }
        return try message.serializedData()
    }

    /// Agency `1`'s REST feed and the Obaco regional feed each carry an alert
    /// of their own; every other agency's REST feed is empty.
    private func stubAlertFeeds() throws {
        dataLoader.mock(data: try feed(alertIDs: ["regional-alert"])) { $0.url?.path.hasSuffix("/alerts-for-agency/1.pb") ?? false }
        dataLoader.mock(data: try feed(alertIDs: [])) { $0.url?.path.contains("/alerts-for-agency/") ?? false }
        dataLoader.mock(data: try feed(alertIDs: ["obaco-alert"])) { $0.url?.path.hasSuffix("/alerts.pb") ?? false }
    }

    /// Answers a URL whose path ends with `suffix` with an empty 500. The first
    /// matching stub wins, so call this before the stubs it should override.
    private func failRequests(endingWith suffix: String) {
        dataLoader.mock(data: Data(), statusCode: 500) { $0.url?.path.hasSuffix(suffix) ?? false }
    }

    private func expectServerError(_ outcome: AlertsOutcomeDelegate.Outcome, sourceLocation: SourceLocation = #_sourceLocation) {
        guard case .failed(let error) = outcome, case .requestFailure(let response)? = error as? APIError else {
            Issue.record("Expected the 500 to reach delegates as APIError.requestFailure, got \(outcome)", sourceLocation: sourceLocation)
            return
        }
        #expect(response.statusCode == 500, sourceLocation: sourceLocation)
    }

    // MARK: - checkForUpdates

    @Test func `Check for updates stores the alerts from both feeds and tells delegates`() async throws {
        stubAgenciesWithCoverage(dataLoader: dataLoader)
        try stubAlertFeeds()

        let outcome = await checkForUpdates()

        guard case .updated = outcome else {
            Issue.record("Expected an update, got \(outcome)")
            return
        }
        #expect(Set(store.agencyAlerts.map(\.id)) == ["regional-alert", "obaco-alert"])
    }

    @Test func `A failed agency list fetch reaches delegates as an error`() async {
        failRequests(endingWith: "/api/where/agencies-with-coverage.json")

        expectServerError(await checkForUpdates())
    }

    @Test func `A failed Obaco alerts fetch reaches delegates as an error`() async throws {
        failRequests(endingWith: "/alerts.pb")
        stubAgenciesWithCoverage(dataLoader: dataLoader)
        try stubAlertFeeds()

        expectServerError(await checkForUpdates())
    }
}
