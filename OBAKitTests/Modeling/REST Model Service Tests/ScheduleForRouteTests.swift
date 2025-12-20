//
//  ScheduleForRouteTests.swift
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

class ScheduleForRouteTests: OBATestCase {
    let routeID = "1_100223"

    override func setUp() {
        super.setUp()

        let dataLoader = (restService.dataLoader as! MockDataLoader)
        dataLoader.mock(
            URLString: "https://www.example.com/api/where/schedule-for-route/\(routeID).json",
            with: Fixtures.loadData(file: "schedule-for-route_1_100223.json")
        )
    }

    // MARK: - URL Builder Tests

    func test_urlBuilder_generatesCorrectURL() {
        let url = restService.urlBuilder.getScheduleForRoute(id: routeID)
        expect(url.absoluteString).to(contain("/api/where/schedule-for-route/\(routeID).json"))
    }

    func test_urlBuilder_withDate_includesDateParameter() {
        let date = Date(timeIntervalSince1970: 1765008000) // 2025-12-06
        let url = restService.urlBuilder.getScheduleForRoute(id: routeID, date: date)
        expect(url.absoluteString).to(contain("date="))
    }

    // MARK: - Model Decoding Tests

    func test_loading_success() async throws {
        let response = try await restService.getScheduleForRoute(routeID: routeID)
        let schedule = response.entry

        expect(schedule.routeID) == "1_100223"
        expect(schedule.scheduleDate).toNot(beNil())
        expect(schedule.serviceIDs).toNot(beEmpty())
        expect(schedule.stopTripGroupings).toNot(beEmpty())
    }

    func test_stopTripGroupings_parsing() async throws {
        let response = try await restService.getScheduleForRoute(routeID: routeID)
        let schedule = response.entry

        let grouping = try XCTUnwrap(schedule.stopTripGroupings.first)
        expect(grouping.directionID).toNot(beNil())
        expect(grouping.stopIDs).toNot(beEmpty())
        expect(grouping.tripHeadsigns).toNot(beEmpty())
        expect(grouping.tripIDs).toNot(beEmpty())
        expect(grouping.tripsWithStopTimes).toNot(beEmpty())
    }

    func test_tripsWithStopTimes_parsing() async throws {
        let response = try await restService.getScheduleForRoute(routeID: routeID)
        let schedule = response.entry

        let grouping = try XCTUnwrap(schedule.stopTripGroupings.first)
        let tripWithStopTimes = try XCTUnwrap(grouping.tripsWithStopTimes.first)

        expect(tripWithStopTimes.tripID).toNot(beEmpty())
        expect(tripWithStopTimes.stopTimes).toNot(beEmpty())
    }

    func test_stopTimes_parsing() async throws {
        let response = try await restService.getScheduleForRoute(routeID: routeID)
        let schedule = response.entry

        let grouping = try XCTUnwrap(schedule.stopTripGroupings.first)
        let tripWithStopTimes = try XCTUnwrap(grouping.tripsWithStopTimes.first)
        let stopTime = try XCTUnwrap(tripWithStopTimes.stopTimes.first)

        expect(stopTime.stopID).toNot(beEmpty())
        expect(stopTime.tripID).toNot(beEmpty())
        // arrivalTime and departureTime are in seconds from midnight
        expect(stopTime.arrivalTime).to(beGreaterThan(0))
        expect(stopTime.departureTime).to(beGreaterThan(0))
        expect(stopTime.arrivalEnabled).to(beTrue())
        expect(stopTime.departureEnabled).to(beTrue())
    }

    func test_arrivalTime_isSecondsFromMidnight() async throws {
        let response = try await restService.getScheduleForRoute(routeID: routeID)
        let schedule = response.entry

        let grouping = try XCTUnwrap(schedule.stopTripGroupings.first)
        let tripWithStopTimes = try XCTUnwrap(grouping.tripsWithStopTimes.first)
        let stopTime = try XCTUnwrap(tripWithStopTimes.stopTimes.first)

        // The fixture has arrivalTime: 31500 which equals 8:45 AM (31500 / 3600 = 8.75 hours)
        // Times should be between 0 (midnight) and 86400 (next midnight) or slightly beyond for overnight routes
        expect(stopTime.arrivalTime).to(beGreaterThanOrEqualTo(0))
        expect(stopTime.arrivalTime).to(beLessThan(86400 * 2)) // Allow for overnight schedules
    }

    // MARK: - References Tests

    func test_references_containsRoutes() async throws {
        let response = try await restService.getScheduleForRoute(routeID: routeID)

        expect(response.references).toNot(beNil())
        expect(response.references?.routes).toNot(beEmpty())
    }

    func test_references_containsStops() async throws {
        let response = try await restService.getScheduleForRoute(routeID: routeID)

        expect(response.references).toNot(beNil())
        expect(response.references?.stops).toNot(beEmpty())
    }
}
