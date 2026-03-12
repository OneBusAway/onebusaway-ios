//
//  ArrivalDepartureFilterTests.swift
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

/// Tests for `ArrivalDepartureFilter` and `[ArrivalDeparture].filter(by:)`.
class ArrivalDepartureFilterTests: OBATestCase {

    // MARK: - Fixture Setup

    private let stopWithRealtime = "1_75403"
    private let stopWithoutRealtime = "1_10020"

    private func makeUrlString(stopID: StopID) -> String {
        "https://www.example.com/api/where/arrivals-and-departures-for-stop/\(stopID).json"
    }

    override func setUp() {
        super.setUp()

        let dataLoader = (restService.dataLoader as! MockDataLoader)

        dataLoader.mock(
            URLString: makeUrlString(stopID: stopWithRealtime),
            with: Fixtures.loadData(file: "arrivals_and_departures_for_stop_1_75403.json")
        )

        dataLoader.mock(
            URLString: makeUrlString(stopID: stopWithoutRealtime),
            with: Fixtures.loadData(file: "arrivals_and_departures_for_stop_1_10020_no_realtime.json")
        )
    }

    // MARK: - Empty Array

    func test_filterByAll_emptyArray_returnsEmpty() {
        let empty: [ArrivalDeparture] = []
        let result = empty.filter(by: .all)
        expect(result).to(beEmpty())
    }

    func test_filterByEstimatedOnly_emptyArray_returnsEmpty() {
        let empty: [ArrivalDeparture] = []
        let result = empty.filter(by: .estimatedOnly)
        expect(result).to(beEmpty())
    }

    func test_filterByScheduledOnly_emptyArray_returnsEmpty() {
        let empty: [ArrivalDeparture] = []
        let result = empty.filter(by: .scheduledOnly)
        expect(result).to(beEmpty())
    }

    // MARK: - Filter .all

    func test_filterByAll_returnsAllArrivals() async throws {
        let stopArrivals = try await restService.getArrivalsAndDeparturesForStop(
            id: stopWithRealtime,
            minutesBefore: 0,
            minutesAfter: 60
        ).entry
        let allArrivals = stopArrivals.arrivalsAndDepartures

        let result = allArrivals.filter(by: .all)
        expect(result.count) == allArrivals.count
    }

    // MARK: - Filter .estimatedOnly

    func test_filterByEstimatedOnly_returnsOnlyPredicted() async throws {
        let stopArrivals = try await restService.getArrivalsAndDeparturesForStop(
            id: stopWithRealtime,
            minutesBefore: 0,
            minutesAfter: 60
        ).entry
        let allArrivals = stopArrivals.arrivalsAndDepartures

        let result = allArrivals.filter(by: .estimatedOnly)

        expect(result).toNot(beEmpty())
        for arrDep in result {
            expect(arrDep.predicted) == true
        }
        expect(result.count) == allArrivals.filter({ $0.predicted }).count
    }

    func test_filterByEstimatedOnly_noRealtimeData_returnsEmpty() async throws {
        let stopArrivals = try await restService.getArrivalsAndDeparturesForStop(
            id: stopWithoutRealtime,
            minutesBefore: 0,
            minutesAfter: 60
        ).entry
        let allArrivals = stopArrivals.arrivalsAndDepartures

        let predictedCount = allArrivals.filter({ $0.predicted }).count
        let result = allArrivals.filter(by: .estimatedOnly)
        expect(result.count) == predictedCount
    }

    // MARK: - Filter .scheduledOnly

    func test_filterByScheduledOnly_returnsOnlyNonPredicted() async throws {
        let stopArrivals = try await restService.getArrivalsAndDeparturesForStop(
            id: stopWithRealtime,
            minutesBefore: 0,
            minutesAfter: 60
        ).entry
        let allArrivals = stopArrivals.arrivalsAndDepartures

        let result = allArrivals.filter(by: .scheduledOnly)

        for arrDep in result {
            expect(arrDep.predicted) == false
        }
        expect(result.count) == allArrivals.filter({ !$0.predicted }).count
    }

    // MARK: - Complementary Counts

    func test_estimatedAndScheduledCountsEqualTotal() async throws {
        let stopArrivals = try await restService.getArrivalsAndDeparturesForStop(
            id: stopWithRealtime,
            minutesBefore: 0,
            minutesAfter: 60
        ).entry
        let allArrivals = stopArrivals.arrivalsAndDepartures

        let estimated = allArrivals.filter(by: .estimatedOnly)
        let scheduled = allArrivals.filter(by: .scheduledOnly)

        expect(estimated.count + scheduled.count) == allArrivals.count
    }
}

// MARK: - ArrivalDepartureFilter Enum Tests

class ArrivalDepartureFilterEnumTests: XCTestCase {

    func test_rawValues() {
        expect(ArrivalDepartureFilter.all.rawValue) == "all"
        expect(ArrivalDepartureFilter.estimatedOnly.rawValue) == "estimatedOnly"
        expect(ArrivalDepartureFilter.scheduledOnly.rawValue) == "scheduledOnly"
    }

    func test_initFromRawValue() {
        expect(ArrivalDepartureFilter(rawValue: "all")) == .all
        expect(ArrivalDepartureFilter(rawValue: "estimatedOnly")) == .estimatedOnly
        expect(ArrivalDepartureFilter(rawValue: "scheduledOnly")) == .scheduledOnly
        expect(ArrivalDepartureFilter(rawValue: "invalid")).to(beNil())
    }

    func test_caseIterable_containsAllCases() {
        expect(ArrivalDepartureFilter.allCases.count) == 3
        expect(ArrivalDepartureFilter.allCases).to(contain(.all, .estimatedOnly, .scheduledOnly))
    }
}

// MARK: - UserDefaults Integration Tests

class ArrivalDepartureFilterUserDefaultsTests: XCTestCase {

    private var userDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: String(describing: self))!
        userDefaults.removePersistentDomain(forName: String(describing: self))
    }

    override func tearDown() {
        super.tearDown()
        userDefaults.removePersistentDomain(forName: String(describing: self))
    }

    func test_noSavedValue_returnsNil() {
        let saved = userDefaults.string(forKey: CoreAppConfig.arrivalDepartureFilterUserDefaultsKey)
        expect(saved).to(beNil())
    }

    func test_savedValue_roundtrips() {
        userDefaults.set(ArrivalDepartureFilter.estimatedOnly.rawValue, forKey: CoreAppConfig.arrivalDepartureFilterUserDefaultsKey)
        let saved = userDefaults.string(forKey: CoreAppConfig.arrivalDepartureFilterUserDefaultsKey)
        let filter = ArrivalDepartureFilter(rawValue: saved ?? "")
        expect(filter) == .estimatedOnly
    }

    func test_savedValue_scheduledOnly_roundtrips() {
        userDefaults.set(ArrivalDepartureFilter.scheduledOnly.rawValue, forKey: CoreAppConfig.arrivalDepartureFilterUserDefaultsKey)
        let saved = userDefaults.string(forKey: CoreAppConfig.arrivalDepartureFilterUserDefaultsKey)
        let filter = ArrivalDepartureFilter(rawValue: saved ?? "")
        expect(filter) == .scheduledOnly
    }

    func test_invalidSavedValue_returnsNil() {
        userDefaults.set("garbage", forKey: CoreAppConfig.arrivalDepartureFilterUserDefaultsKey)
        let saved = userDefaults.string(forKey: CoreAppConfig.arrivalDepartureFilterUserDefaultsKey)
        let filter = ArrivalDepartureFilter(rawValue: saved ?? "")
        expect(filter).to(beNil())
    }
}
