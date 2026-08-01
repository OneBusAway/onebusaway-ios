//
//  ArrivalDepartureFilterTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast

@Suite(.serialized)
final class ArrivalDepartureFilterTests: OBATestCase {

    // MARK: - Fixture Setup

    private let stopWithRealtime = "1_75403"
    private let stopWithoutRealtime = "1_10020"

    private func makeUrlString(stopID: StopID) -> String {
        "https://www.example.com/api/where/arrivals-and-departures-for-stop/\(stopID).json"
    }

    override init() async throws {
        try await super.init()

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

    @Test func `Filter by all on empty array returns empty`() {
        #expect([ArrivalDeparture]().filter(by: .all).isEmpty)
    }

    @Test func `Filter by estimated only on empty array returns empty`() {
        #expect([ArrivalDeparture]().filter(by: .estimatedOnly).isEmpty)
    }

    @Test func `Filter by scheduled only on empty array returns empty`() {
        #expect([ArrivalDeparture]().filter(by: .scheduledOnly).isEmpty)
    }

    // MARK: - Filter .all

    @Test func `Filter by all returns all arrivals`() async throws {
        let stopArrivals = try await restService.getArrivalsAndDeparturesForStop(
            id: stopWithRealtime, minutesBefore: 0, minutesAfter: 60
        ).entry
        let allArrivals = stopArrivals.arrivalsAndDepartures

        #expect(allArrivals.filter(by: .all).count == allArrivals.count)
    }

    // MARK: - Filter .estimatedOnly

    @Test func `Filter by estimated only returns only predicted`() async throws {
        let stopArrivals = try await restService.getArrivalsAndDeparturesForStop(
            id: stopWithRealtime, minutesBefore: 0, minutesAfter: 60
        ).entry
        let allArrivals = stopArrivals.arrivalsAndDepartures
        let result = allArrivals.filter(by: .estimatedOnly)

        #expect(!result.isEmpty)
        for arrDep in result {
            #expect(arrDep.predicted)
        }
        #expect(result.count == allArrivals.filter({ $0.predicted }).count)
    }

    @Test func `Filter by estimated only with no realtime data returns empty`() async throws {
        let stopArrivals = try await restService.getArrivalsAndDeparturesForStop(
            id: stopWithoutRealtime, minutesBefore: 0, minutesAfter: 60
        ).entry
        let allArrivals = stopArrivals.arrivalsAndDepartures

        #expect(!allArrivals.isEmpty)
        #expect(allArrivals.filter(by: .estimatedOnly).isEmpty)
    }

    // MARK: - Filter .scheduledOnly

    @Test func `Filter by scheduled only returns only non-predicted`() async throws {
        let stopArrivals = try await restService.getArrivalsAndDeparturesForStop(
            id: stopWithRealtime, minutesBefore: 0, minutesAfter: 60
        ).entry
        let allArrivals = stopArrivals.arrivalsAndDepartures
        let result = allArrivals.filter(by: .scheduledOnly)

        for arrDep in result {
            #expect(!arrDep.predicted)
        }
        #expect(result.count == allArrivals.filter({ !$0.predicted }).count)
    }

    @Test func `Filter by scheduled only with no realtime data returns all`() async throws {
        let stopArrivals = try await restService.getArrivalsAndDeparturesForStop(
            id: stopWithoutRealtime, minutesBefore: 0, minutesAfter: 60
        ).entry
        let allArrivals = stopArrivals.arrivalsAndDepartures

        #expect(!allArrivals.isEmpty)
        #expect(allArrivals.filter(by: .scheduledOnly).count == allArrivals.count)
    }

    @Test func `Filter by all with no realtime data returns all`() async throws {
        let stopArrivals = try await restService.getArrivalsAndDeparturesForStop(
            id: stopWithoutRealtime, minutesBefore: 0, minutesAfter: 60
        ).entry
        let allArrivals = stopArrivals.arrivalsAndDepartures

        #expect(!allArrivals.isEmpty)
        #expect(allArrivals.filter(by: .all).count == allArrivals.count)
    }

    // MARK: - Complementary Counts

    @Test func `Estimated and scheduled counts equal total`() async throws {
        let stopArrivals = try await restService.getArrivalsAndDeparturesForStop(
            id: stopWithRealtime, minutesBefore: 0, minutesAfter: 60
        ).entry
        let allArrivals = stopArrivals.arrivalsAndDepartures

        let estimated = allArrivals.filter(by: .estimatedOnly)
        let scheduled = allArrivals.filter(by: .scheduledOnly)

        #expect(estimated.count + scheduled.count == allArrivals.count)
    }
}

// MARK: - ArrivalDepartureFilter Enum Tests

@Suite
struct ArrivalDepartureFilterEnumTests {

    @Test func `Raw values are correct`() {
        #expect(ArrivalDepartureFilter.all.rawValue == "all")
        #expect(ArrivalDepartureFilter.estimatedOnly.rawValue == "estimatedOnly")
        #expect(ArrivalDepartureFilter.scheduledOnly.rawValue == "scheduledOnly")
    }

    @Test func `Init from raw value works`() {
        #expect(ArrivalDepartureFilter(rawValue: "all") == .all)
        #expect(ArrivalDepartureFilter(rawValue: "estimatedOnly") == .estimatedOnly)
        #expect(ArrivalDepartureFilter(rawValue: "scheduledOnly") == .scheduledOnly)
        #expect(ArrivalDepartureFilter(rawValue: "invalid") == nil)
    }

    @Test func `CaseIterable contains all cases`() {
        #expect(ArrivalDepartureFilter.allCases.count == 3)
        #expect(ArrivalDepartureFilter.allCases.contains(.all))
        #expect(ArrivalDepartureFilter.allCases.contains(.estimatedOnly))
        #expect(ArrivalDepartureFilter.allCases.contains(.scheduledOnly))
    }
}

// MARK: - UserDefaults Integration Tests

@Suite(.serialized)
struct ArrivalDepartureFilterUserDefaultsTests {

    private let userDefaults: UserDefaults

    init() {
        userDefaults = UserDefaults(suiteName: "ArrivalDepartureFilterUserDefaultsTests")!
        userDefaults.removePersistentDomain(forName: "ArrivalDepartureFilterUserDefaultsTests")
    }

    @Test func `No saved value is nil`() {
        #expect(userDefaults.string(forKey: CoreAppConfig.arrivalDepartureFilterUserDefaultsKey) == nil)
    }

    @Test func `Saved estimatedOnly round trips`() {
        userDefaults.set(ArrivalDepartureFilter.estimatedOnly.rawValue, forKey: CoreAppConfig.arrivalDepartureFilterUserDefaultsKey)
        let saved = userDefaults.string(forKey: CoreAppConfig.arrivalDepartureFilterUserDefaultsKey)
        #expect(ArrivalDepartureFilter(rawValue: saved ?? "") == .estimatedOnly)
    }

    @Test func `Saved scheduledOnly round trips`() {
        userDefaults.set(ArrivalDepartureFilter.scheduledOnly.rawValue, forKey: CoreAppConfig.arrivalDepartureFilterUserDefaultsKey)
        let saved = userDefaults.string(forKey: CoreAppConfig.arrivalDepartureFilterUserDefaultsKey)
        #expect(ArrivalDepartureFilter(rawValue: saved ?? "") == .scheduledOnly)
    }

    @Test func `Invalid saved value returns nil`() {
        userDefaults.set("garbage", forKey: CoreAppConfig.arrivalDepartureFilterUserDefaultsKey)
        let saved = userDefaults.string(forKey: CoreAppConfig.arrivalDepartureFilterUserDefaultsKey)
        #expect(ArrivalDepartureFilter(rawValue: saved ?? "") == nil)
    }

    @Test func `Nil value with configured default resolves to default`() {
        let saved = userDefaults.string(forKey: CoreAppConfig.arrivalDepartureFilterUserDefaultsKey)
        #expect(ArrivalDepartureFilter(rawValue: saved ?? "") ?? .scheduledOnly == .scheduledOnly)
    }

    @Test func `Invalid value with configured default resolves to default`() {
        userDefaults.set("garbage", forKey: CoreAppConfig.arrivalDepartureFilterUserDefaultsKey)
        let saved = userDefaults.string(forKey: CoreAppConfig.arrivalDepartureFilterUserDefaultsKey)
        #expect(ArrivalDepartureFilter(rawValue: saved ?? "") ?? .estimatedOnly == .estimatedOnly)
    }
}
