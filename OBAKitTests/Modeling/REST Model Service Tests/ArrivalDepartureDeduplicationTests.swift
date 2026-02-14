//
//  ArrivalDepartureDeduplicationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast

/// Tests for `[ArrivalDeparture].filteringTerminalDuplicates()`.
///
/// Validates the deduplication logic that removes visually identical
/// arrival/departure rows caused by terminal stops returning both an arrival
/// and a departure entry for the same trip at the same stop.
class ArrivalDepartureDeduplicationTests: OBATestCase {

    // MARK: - Fixture Setup

    private let galerStopID = "1_11370"
    private let campusParkwayStopID = "1_10914"

    private func makeUrlString(stopID: StopID) -> String {
        "https://www.example.com/api/where/arrivals-and-departures-for-stop/\(stopID).json"
    }

    override func setUp() {
        super.setUp()

        let dataLoader = (restService.dataLoader as! MockDataLoader)

        dataLoader.mock(
            URLString: makeUrlString(stopID: galerStopID),
            with: Fixtures.loadData(file: "arrivals_and_departures_for_stop_15th-galer.json")
        )

        dataLoader.mock(
            URLString: makeUrlString(stopID: campusParkwayStopID),
            with: Fixtures.loadData(file: "arrivals-and-departures-for-stop-1_10914.json")
        )
    }

    // MARK: - Basic Behavior

    /// An empty array returns an empty array without crashing.
    func test_filteringTerminalDuplicates_handlesEmptyArray() {
        let empty: [ArrivalDeparture] = []
        let filtered = empty.filteringTerminalDuplicates()
        expect(filtered).to(beEmpty())
    }

    /// A single-element array passes through unchanged.
    func test_filteringTerminalDuplicates_handlesSingleElement() async throws {
        let arrivals = try await restService.getArrivalsAndDeparturesForStop(
            id: campusParkwayStopID, minutesBefore: 5, minutesAfter: 30
        ).entry

        expect(arrivals.arrivalsAndDepartures.count) == 1

        let filtered = arrivals.arrivalsAndDepartures.filteringTerminalDuplicates()
        expect(filtered.count) == 1
        expect(filtered[0].tripID) == arrivals.arrivalsAndDepartures[0].tripID
        expect(filtered[0].stopID) == arrivals.arrivalsAndDepartures[0].stopID
    }

    // MARK: - No False Positives

    /// The Galer fixture has entries that share a vehicleID but have different tripIDs.
    /// These are different trips on the same vehicle block — NOT terminal duplicates.
    /// The filter must preserve all of them.
    func test_filteringTerminalDuplicates_preservesDifferentTripsOnSameVehicle() async throws {
        let arrivals = try await restService.getArrivalsAndDeparturesForStop(
            id: galerStopID, minutesBefore: 5, minutesAfter: 30
        ).entry

        let arrDeps = arrivals.arrivalsAndDepartures
        expect(arrDeps.count) == 5

        // Pre-condition: entries [0] and [1] share a vehicleID but have different tripIDs.
        // They are different trips on the same block, not terminal duplicates.
        expect(arrDeps[0].vehicleID) == "1_4361"
        expect(arrDeps[1].vehicleID) == "1_4361"
        expect(arrDeps[0].tripID).toNot(equal(arrDeps[1].tripID))

        let filtered = arrDeps.filteringTerminalDuplicates()

        // All 5 entries should be preserved because they all have unique (tripID, stopID, routeID).
        expect(filtered.count) == arrDeps.count
    }

    /// A fixture with no terminal duplicates should pass through completely unchanged.
    func test_filteringTerminalDuplicates_noFalsePositivesOnCleanData() async throws {
        let arrivals = try await restService.getArrivalsAndDeparturesForStop(
            id: campusParkwayStopID, minutesBefore: 5, minutesAfter: 30
        ).entry

        let arrDeps = arrivals.arrivalsAndDepartures
        expect(arrDeps.count) == 1

        let filtered = arrDeps.filteringTerminalDuplicates()
        expect(filtered.count) == 1
        expect(filtered[0].id) == arrDeps[0].id
    }

    // MARK: - Duplicate Detection (Synthetic)

    /// When two entries share the exact same (tripID, stopID, routeID),
    /// only one should survive. This simulates the terminal duplicate scenario
    /// by appending the same ArrivalDeparture entry to the array.
    func test_filteringTerminalDuplicates_removesDuplicateVisits() async throws {
        let arrivals = try await restService.getArrivalsAndDeparturesForStop(
            id: campusParkwayStopID, minutesBefore: 5, minutesAfter: 30
        ).entry

        let arrDeps = arrivals.arrivalsAndDepartures
        expect(arrDeps.count) == 1

        // Simulate a terminal duplicate: same object appended twice.
        var duplicated = arrDeps
        duplicated.append(arrDeps[0])
        expect(duplicated.count) == 2

        let filtered = duplicated.filteringTerminalDuplicates()

        // The duplicate should be merged, leaving only one entry.
        expect(filtered.count) == 1
        expect(filtered[0].tripID) == arrDeps[0].tripID
    }

    /// When multiple distinct entries exist alongside a duplicate pair,
    /// only the duplicate pair is merged. All other entries are preserved.
    func test_filteringTerminalDuplicates_mergesOnlyDuplicatesAmongDistinctEntries() async throws {
        let arrivals = try await restService.getArrivalsAndDeparturesForStop(
            id: galerStopID, minutesBefore: 5, minutesAfter: 30
        ).entry

        let arrDeps = arrivals.arrivalsAndDepartures
        expect(arrDeps.count) == 5

        // Append a duplicate of entry [0] to create exactly one duplicate pair.
        var withDuplicate = arrDeps
        withDuplicate.append(arrDeps[0])
        expect(withDuplicate.count) == 6

        let filtered = withDuplicate.filteringTerminalDuplicates()

        // Only the appended duplicate should be removed; original 5 entries preserved.
        expect(filtered.count) == 5
    }

    // MARK: - Ordering

    /// The relative order of entries is preserved after filtering.
    func test_filteringTerminalDuplicates_preservesOriginalOrder() async throws {
        let arrivals = try await restService.getArrivalsAndDeparturesForStop(
            id: galerStopID, minutesBefore: 5, minutesAfter: 30
        ).entry

        let arrDeps = arrivals.arrivalsAndDepartures
        let filtered = arrDeps.filteringTerminalDuplicates()

        let filteredIDs = filtered.map { $0.id }
        var lastInputIndex = -1
        for filteredID in filteredIDs {
            guard let inputIndex = arrDeps.firstIndex(where: { $0.id == filteredID }) else {
                XCTFail("Filtered entry with id \(filteredID) not found in original array")
                continue
            }
            expect(inputIndex).to(beGreaterThan(lastInputIndex), description: "Original ordering must be preserved")
            lastInputIndex = inputIndex
        }
    }

    // MARK: - Idempotency

    /// Applying the filter twice produces the same result as applying it once.
    func test_filteringTerminalDuplicates_isIdempotent() async throws {
        let arrivals = try await restService.getArrivalsAndDeparturesForStop(
            id: galerStopID, minutesBefore: 5, minutesAfter: 30
        ).entry

        let once = arrivals.arrivalsAndDepartures.filteringTerminalDuplicates()
        let twice = once.filteringTerminalDuplicates()

        expect(twice.count) == once.count
        for (a, b) in zip(once, twice) {
            expect(a.id) == b.id
        }
    }

    // MARK: - Preference Logic

    /// When both a predicted and non-predicted entry exist for the same visit,
    /// the predicted (real-time) entry should be kept.
    func test_filteringTerminalDuplicates_prefersRealTimeOverScheduled() async throws {
        let arrivals = try await restService.getArrivalsAndDeparturesForStop(
            id: campusParkwayStopID, minutesBefore: 5, minutesAfter: 30
        ).entry

        let arrDeps = arrivals.arrivalsAndDepartures
        guard let entry = arrDeps.first else {
            XCTFail("Fixture must contain at least one ArrivalDeparture")
            return
        }

        // This entry has predicted == true.
        expect(entry.predicted).to(beTrue())

        // Create a pair with the same identity. Both are the same object
        // (both predicted), so the first-in should win.
        let pair = [entry, entry]
        let filtered = pair.filteringTerminalDuplicates()

        expect(filtered.count) == 1
        expect(filtered[0].predicted).to(beTrue())
        expect(filtered[0].tripID) == entry.tripID
    }
}
