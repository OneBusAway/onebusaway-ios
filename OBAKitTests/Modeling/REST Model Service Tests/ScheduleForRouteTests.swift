//
//  ScheduleForRouteTests.swift
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

// swiftlint:disable force_cast

@Suite(.serialized)
final class ScheduleForRouteTests: OBATestCase {
    let routeID = "1_100223"

    override init() async throws {
        try await super.init()

        let dataLoader = (restService.dataLoader as! MockDataLoader)
        dataLoader.mock(
            URLString: "https://www.example.com/api/where/schedule-for-route/\(routeID).json",
            with: Fixtures.loadData(file: "schedule-for-route_1_100223.json")
        )
    }

    // MARK: - URL Builder Tests

    @Test func `Url builder generates correct URL`() {
        let url = restService.urlBuilder.getScheduleForRoute(id: routeID)
        #expect(url.absoluteString.contains("/api/where/schedule-for-route/\(routeID).json"))
    }

    @Test func `Url builder with date includes date parameter`() {
        let date = Date(timeIntervalSince1970: 1765008000) // 2025-12-06
        let url = restService.urlBuilder.getScheduleForRoute(id: routeID, date: date)
        #expect(url.absoluteString.contains("date="))
    }

    // MARK: - Model Decoding Tests

    @Test func `Loading success`() async throws {
        let response = try await restService.getScheduleForRoute(routeID: routeID)
        let schedule = response.entry

        #expect(schedule.routeID == "1_100223")
        #expect(!schedule.serviceIDs.isEmpty)
        #expect(!schedule.stopTripGroupings.isEmpty)
    }

    @Test func `Stop trip groupings parsing`() async throws {
        let response = try await restService.getScheduleForRoute(routeID: routeID)
        let schedule = response.entry

        let grouping = try #require(schedule.stopTripGroupings.first)
        #expect(!grouping.stopIDs.isEmpty)
        #expect(!grouping.tripHeadsigns.isEmpty)
        #expect(!grouping.tripIDs.isEmpty)
        #expect(!grouping.tripsWithStopTimes.isEmpty)
    }

    @Test func `Trips with stop times parsing`() async throws {
        let response = try await restService.getScheduleForRoute(routeID: routeID)
        let schedule = response.entry

        let grouping = try #require(schedule.stopTripGroupings.first)
        let tripWithStopTimes = try #require(grouping.tripsWithStopTimes.first)

        #expect(!tripWithStopTimes.tripID.isEmpty)
        #expect(!tripWithStopTimes.stopTimes.isEmpty)
    }

    @Test func `Stop times parsing`() async throws {
        let response = try await restService.getScheduleForRoute(routeID: routeID)
        let schedule = response.entry

        let grouping = try #require(schedule.stopTripGroupings.first)
        let tripWithStopTimes = try #require(grouping.tripsWithStopTimes.first)
        let stopTime = try #require(tripWithStopTimes.stopTimes.first)

        #expect(!stopTime.stopID.isEmpty)
        #expect(!stopTime.tripID.isEmpty)
        // arrivalTime and departureTime are in seconds from midnight
        #expect(stopTime.arrivalTime > 0)
        #expect(stopTime.departureTime > 0)
        #expect(stopTime.arrivalEnabled)
        #expect(stopTime.departureEnabled)
    }

    @Test func `Arrival time is seconds from midnight`() async throws {
        let response = try await restService.getScheduleForRoute(routeID: routeID)
        let schedule = response.entry

        let grouping = try #require(schedule.stopTripGroupings.first)
        let tripWithStopTimes = try #require(grouping.tripsWithStopTimes.first)
        let stopTime = try #require(tripWithStopTimes.stopTimes.first)

        // The fixture has arrivalTime: 31500 which equals 8:45 AM (31500 / 3600 = 8.75 hours)
        // Times should be between 0 (midnight) and 86400 (next midnight) or slightly beyond for overnight routes
        #expect(stopTime.arrivalTime >= 0)
        #expect(stopTime.arrivalTime < 86400 * 2)  // Allow for overnight schedules
    }

    // MARK: - References Tests

    @Test func `References contains routes`() async throws {
        let response = try await restService.getScheduleForRoute(routeID: routeID)

        #expect(response.references != nil)
        #expect(response.references?.routes.isEmpty == false)
    }

    @Test func `References contains stops`() async throws {
        let response = try await restService.getScheduleForRoute(routeID: routeID)

        #expect(response.references != nil)
        #expect(response.references?.stops.isEmpty == false)
    }
}
