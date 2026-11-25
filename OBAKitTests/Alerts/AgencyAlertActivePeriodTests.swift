//
//  AgencyAlertActivePeriodTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Synchronization
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Tests for `AgencyAlert.isActive(at:)`, `hasActivePeriod`, and the
/// safe handling of corrupt GTFS-RT active period timestamps.
@Suite(.serialized)
final class AgencyAlertActivePeriodTests: OBATestCase {

    // MARK: - Helpers

    /// Builds a region-wide alert with the given active periods.
    private func makeAlert(
        activePeriods: [TransitRealtime_TimeRange],
        id: String = "Alert_Active_Test"
    ) throws -> AgencyAlert {
        var entitySelector = TransitRealtime_EntitySelector()
        entitySelector.agencyID = ""

        var header = TransitRealtime_TranslatedString()
        var translation = TransitRealtime_TranslatedString.Translation()
        translation.language = "en"
        translation.text = "Test Alert"
        header.translation = [translation]

        var alert = TransitRealtime_Alert()
        alert.severityLevel = .warning
        alert.activePeriod = activePeriods
        alert.informedEntity = [entitySelector]
        alert.headerText = header

        var feedEntity = TransitRealtime_FeedEntity()
        feedEntity.id = id
        feedEntity.alert = alert

        return try AgencyAlert(feedEntity: feedEntity, agency: nil)
    }

    private func period(start: UInt64?, end: UInt64?) -> TransitRealtime_TimeRange {
        var p = TransitRealtime_TimeRange()
        if let start { p.start = start }
        if let end { p.end = end }
        return p
    }

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private var pastTimestamp: UInt64 {
        UInt64(now.addingTimeInterval(-3600).timeIntervalSince1970)  // 1 hour ago
    }

    private var futureTimestamp: UInt64 {
        UInt64(now.addingTimeInterval(3600).timeIntervalSince1970)   // 1 hour from now
    }

    private var farPastTimestamp: UInt64 {
        UInt64(now.addingTimeInterval(-7200).timeIntervalSince1970)  // 2 hours ago
    }

    private var farFutureTimestamp: UInt64 {
        UInt64(now.addingTimeInterval(7200).timeIntervalSince1970)   // 2 hours from now
    }

    // MARK: - No active periods ⇒ always active

    @Test func `Alert with no active periods is always active`() throws {
        let alert = try makeAlert(activePeriods: [])
        #expect(alert.isActive(at: now))
        #expect(alert.isActive(at: Date.distantPast))
        #expect(alert.isActive(at: Date.distantFuture))
        #expect(!alert.hasActivePeriod)
    }

    // MARK: - Single active period

    @Test func `Alert active within single period`() throws {
        let p = period(start: pastTimestamp, end: futureTimestamp)
        let alert = try makeAlert(activePeriods: [p])

        #expect(alert.isActive(at: now))
        #expect(alert.hasActivePeriod)
    }

    @Test func `Alert inactive before single period starts`() throws {
        let futureStart = UInt64(now.addingTimeInterval(600).timeIntervalSince1970) // 10 min from now
        let p = period(start: futureStart, end: farFutureTimestamp)
        let alert = try makeAlert(activePeriods: [p])

        #expect(!alert.isActive(at: now))
    }

    @Test func `Alert inactive after single period ends`() throws {
        let p = period(start: farPastTimestamp, end: pastTimestamp) // ended 1 hour ago
        let alert = try makeAlert(activePeriods: [p])

        #expect(!alert.isActive(at: now))
    }

    // MARK: - Open-ended periods (missing start or end)

    @Test func `Alert with no start is active from distant past`() throws {
        var p = TransitRealtime_TimeRange()
        p.end = futureTimestamp
        let alert = try makeAlert(activePeriods: [p])

        #expect(alert.isActive(at: now))
        #expect(alert.isActive(at: Date.distantPast))
    }

    @Test func `Alert with no end is active into distant future`() throws {
        var p = TransitRealtime_TimeRange()
        p.start = pastTimestamp
        let alert = try makeAlert(activePeriods: [p])

        #expect(alert.isActive(at: now))
        #expect(alert.isActive(at: Date.distantFuture))
    }

    @Test func `Period with end set to 0 is treated as open ended`() throws {
        let openEnded = period(start: pastTimestamp, end: 0)
        let alert = try makeAlert(activePeriods: [openEnded])

        #expect(alert.isActive(at: now))
        #expect(alert.isActive(at: Date.distantFuture))
    }

    @Test func `Alert with neither start nor end is always active`() throws {
        let p = TransitRealtime_TimeRange() // no start, no end
        let alert = try makeAlert(activePeriods: [p])

        #expect(alert.isActive(at: now))
        #expect(alert.isActive(at: Date.distantPast))
        #expect(alert.isActive(at: Date.distantFuture))
    }

    // MARK: - Multiple active periods

    @Test func `Alert active when any period covers the date`() throws {
        let expired = period(start: farPastTimestamp, end: pastTimestamp)   // expired
        let current = period(start: pastTimestamp, end: futureTimestamp)    // covers now
        let alert = try makeAlert(activePeriods: [expired, current])

        #expect(alert.isActive(at: now))
    }

    @Test func `Alert inactive when no period covers the date`() throws {
        let old = period(start: farPastTimestamp, end: pastTimestamp)
        let upcoming = period(start: futureTimestamp, end: farFutureTimestamp)
        let alert = try makeAlert(activePeriods: [old, upcoming])

        #expect(!alert.isActive(at: now))
    }

    // MARK: - Corrupt active periods (start > end)

    @Test func `Corrupt period with start after end does not crash`() throws {
        // In Swift, forming a ClosedRange (start...end) where start > end triggers
        // a fatal runtime trap. Direct date comparison avoids trapping and treats
        // the inverted period as inactive.
        let corrupt = period(start: futureTimestamp, end: pastTimestamp) // start > end
        let alert = try makeAlert(activePeriods: [corrupt])

        #expect(!alert.isActive(at: now))
        #expect(alert.sortStartDate(asOf: now) == nil)
    }

    @Test func `Corrupt period among valid periods — valid ones still work`() throws {
        let corrupt = period(start: futureTimestamp, end: pastTimestamp)   // corrupt
        let valid = period(start: pastTimestamp, end: futureTimestamp)     // covers now
        let alert = try makeAlert(activePeriods: [corrupt, valid])

        // The corrupt period is skipped; the valid one makes the alert active.
        #expect(alert.isActive(at: now))
        #expect(alert.activeStartDate(at: now) == Date(timeIntervalSince1970: TimeInterval(pastTimestamp)))
    }

    // MARK: - Boundary conditions (GTFS-RT [start, end))

    @Test func `Alert active at exact start time`() throws {
        let startTS = UInt64(now.timeIntervalSince1970)
        let p = period(start: startTS, end: futureTimestamp)
        let alert = try makeAlert(activePeriods: [p])

        #expect(alert.isActive(at: now))
    }

    @Test func `Alert active one second before end time`() throws {
        let endTS = UInt64(now.addingTimeInterval(1).timeIntervalSince1970)
        let p = period(start: pastTimestamp, end: endTS)
        let alert = try makeAlert(activePeriods: [p])

        #expect(alert.isActive(at: now))
    }

    @Test func `Alert inactive at exact end time`() throws {
        let endTS = UInt64(now.timeIntervalSince1970)
        let p = period(start: pastTimestamp, end: endTS)
        let alert = try makeAlert(activePeriods: [p])

        #expect(!alert.isActive(at: now))
    }

    @Test func `Alert where start equals end is inactive`() throws {
        let ts = UInt64(now.timeIntervalSince1970)
        let p = period(start: ts, end: ts)
        let alert = try makeAlert(activePeriods: [p])

        #expect(!alert.isActive(at: now))
        #expect(!alert.isActive(at: now.addingTimeInterval(1)))
    }

    // MARK: - Multi-period start resolution

    @Test func `activeStartDate and sortStartDate pick active period over older expired period`() throws {
        let expired = period(start: farPastTimestamp, end: pastTimestamp)
        let currentStart = UInt64(now.addingTimeInterval(-600).timeIntervalSince1970)
        let current = period(start: currentStart, end: futureTimestamp)
        let alert = try makeAlert(activePeriods: [expired, current])

        let expected = Date(timeIntervalSince1970: TimeInterval(currentStart))
        #expect(alert.activeStartDate(at: now) == expected)
        #expect(alert.sortStartDate(asOf: now) == expected)
    }

    // MARK: - hasActivePeriod

    @Test func `hasActivePeriod true when periods exist`() throws {
        let p = period(start: pastTimestamp, end: futureTimestamp)
        let alert = try makeAlert(activePeriods: [p])

        #expect(alert.hasActivePeriod)
    }

    @Test func `hasActivePeriod false when no periods`() throws {
        let alert = try makeAlert(activePeriods: [])

        #expect(!alert.hasActivePeriod)
    }

    // MARK: - Corrupt period warning deduplication

    private nonisolated final class WarningRecorder: Sendable {
        private let ids = Mutex<[String]>([])
        var warnedIDs: [String] { ids.withLock { $0 } }
        func record(_ id: String) { ids.withLock { $0.append(id) } }
    }

    private func withCorruptWarningRecorder(
        for alertIDs: Set<String>,
        perform body: (WarningRecorder) async throws -> Void
    ) async throws -> [String] {
        let recorder = WarningRecorder()
        AgencyAlert.onCorruptWarningForTesting = { warnedID in
            if alertIDs.contains(warnedID) {
                recorder.record(warnedID)
            }
        }
        defer { AgencyAlert.onCorruptWarningForTesting = nil }
        try await body(recorder)
        return recorder.warnedIDs
    }

    @Test func `Corrupt period warning logs once per alert ID across calls and instances`() async throws {
        let alertID = "corrupt-once-\(UUID().uuidString)"
        let corrupt = period(start: futureTimestamp, end: pastTimestamp)
        let firstInstance = try makeAlert(activePeriods: [corrupt], id: alertID)
        let refreshedInstance = try makeAlert(activePeriods: [corrupt], id: alertID)

        let warned = try await withCorruptWarningRecorder(for: [alertID]) { _ in
            #expect(!firstInstance.isActive(at: now))
            #expect(!firstInstance.isActive(at: now))
            #expect(!refreshedInstance.isActive(at: now))
        }

        #expect(warned == [alertID])
    }

    @Test func `Multiple corrupt periods on one alert warn only once`() async throws {
        let alertID = "corrupt-multi-\(UUID().uuidString)"
        let firstCorrupt = period(start: futureTimestamp, end: pastTimestamp)
        let secondCorrupt = period(start: farFutureTimestamp, end: farPastTimestamp)
        let alert = try makeAlert(activePeriods: [firstCorrupt, secondCorrupt], id: alertID)

        let warned = try await withCorruptWarningRecorder(for: [alertID]) { _ in
            #expect(!alert.isActive(at: now))
        }

        #expect(warned == [alertID])
    }

    @Test func `Distinct corrupt alert IDs each log one warning`() async throws {
        let firstID = "corrupt-distinct-1-\(UUID().uuidString)"
        let secondID = "corrupt-distinct-2-\(UUID().uuidString)"
        let corrupt = period(start: futureTimestamp, end: pastTimestamp)
        let firstAlert = try makeAlert(activePeriods: [corrupt], id: firstID)
        let secondAlert = try makeAlert(activePeriods: [corrupt], id: secondID)

        let warned = try await withCorruptWarningRecorder(for: [firstID, secondID]) { _ in
            #expect(!firstAlert.isActive(at: now))
            #expect(!firstAlert.isActive(at: now))
            #expect(!secondAlert.isActive(at: now))
            #expect(!secondAlert.isActive(at: now))
        }

        #expect(warned == [firstID, secondID])
    }

    @Test func `sortStartDate and activeStartDate do not suppress the first isActive warning`() async throws {
        let alertID = "corrupt-sort-\(UUID().uuidString)"
        let corrupt = period(start: futureTimestamp, end: pastTimestamp)
        let alert = try makeAlert(activePeriods: [corrupt], id: alertID)

        let warned = try await withCorruptWarningRecorder(for: [alertID]) { recorder in
            #expect(alert.activeStartDate(at: now) == nil)
            #expect(alert.sortStartDate(asOf: now) == nil)
            #expect(recorder.warnedIDs.isEmpty)

            #expect(!alert.isActive(at: now))
        }

        #expect(warned == [alertID])
    }

    private nonisolated func runConcurrentIsActiveChecks(
        alert: AgencyAlert,
        at date: Date,
        iterations: Int
    ) async -> [Bool] {
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<iterations {
                group.addTask {
                    alert.isActive(at: date)
                }
            }
            var results: [Bool] = []
            for await active in group {
                results.append(active)
            }
            return results
        }
    }

    @Test func `Concurrent isActive checks on corrupt alert warn exactly once`() async throws {
        let alertID = "corrupt-concurrent-\(UUID().uuidString)"
        let corrupt = period(start: futureTimestamp, end: pastTimestamp)
        let alert = try makeAlert(activePeriods: [corrupt], id: alertID)
        let checkDate = now

        let warned = try await withCorruptWarningRecorder(for: [alertID]) { _ in
            let results = await runConcurrentIsActiveChecks(alert: alert, at: checkDate, iterations: 25)
            #expect(results.count == 25)
            #expect(results.allSatisfy { !$0 })
        }

        #expect(warned == [alertID])
    }
}
