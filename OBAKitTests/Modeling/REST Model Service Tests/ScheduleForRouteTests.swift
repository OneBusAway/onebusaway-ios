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

    // MARK: - Stop Time Date Calculation Tests

    private func makeStopTime(arrivalTime: Int, departureTime: Int) throws -> ScheduleForRoute.RouteScheduleStopTime {
        let json = """
        {
            "stopId": "1_41902",
            "tripId": "1_761056039",
            "arrivalTime": \(arrivalTime),
            "departureTime": \(departureTime),
            "arrivalEnabled": true,
            "departureEnabled": true,
            "serviceId": "",
            "stopHeadsign": ""
        }
        """
        return try JSONDecoder().decode(ScheduleForRoute.RouteScheduleStopTime.self, from: Data(json.utf8))
    }

    private func makeGregorianDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0,
        timeZone: TimeZone
    ) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return try #require(calendar.date(from: components))
    }

    private func formatHourMinute(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    @Test func `Arrival and departure dates on a standard day match GTFS clock times`() throws {
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let serviceDay = try makeGregorianDate(year: 2025, month: 12, day: 6, timeZone: losAngeles)

        let morning = try makeStopTime(arrivalTime: 31_500, departureTime: 31_560) // 08:45 / 08:46
        #expect(formatHourMinute(morning.arrivalDate(for: serviceDay, timeZone: losAngeles), timeZone: losAngeles) == "2025-12-06 08:45")
        #expect(formatHourMinute(morning.departureDate(for: serviceDay, timeZone: losAngeles), timeZone: losAngeles) == "2025-12-06 08:46")

        let overnight = try makeStopTime(arrivalTime: 91_800, departureTime: 91_860) // 25:30 / 25:31
        #expect(formatHourMinute(overnight.arrivalDate(for: serviceDay, timeZone: losAngeles), timeZone: losAngeles) == "2025-12-07 01:30")
        #expect(formatHourMinute(overnight.departureDate(for: serviceDay, timeZone: losAngeles), timeZone: losAngeles) == "2025-12-07 01:31")
    }

    @Test func `Arrival and departure dates on Spring Forward DST day do not shift forward an hour`() throws {
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let springForwardDay = try makeGregorianDate(year: 2026, month: 3, day: 8, timeZone: losAngeles)

        // 2026-03-08 is a 23-hour day in America/Los_Angeles (02:00 PST -> 03:00 PDT).
        // Per GTFS, times are measured from local noon minus 12h so 08:45 stays 08:45 PDT.
        let morning = try makeStopTime(arrivalTime: 31_500, departureTime: 31_560)
        #expect(formatHourMinute(morning.arrivalDate(for: springForwardDay, timeZone: losAngeles), timeZone: losAngeles) == "2026-03-08 08:45")
        #expect(formatHourMinute(morning.departureDate(for: springForwardDay, timeZone: losAngeles), timeZone: losAngeles) == "2026-03-08 08:46")

        let overnight = try makeStopTime(arrivalTime: 91_800, departureTime: 91_860) // 25:30 / 25:31
        #expect(formatHourMinute(overnight.arrivalDate(for: springForwardDay, timeZone: losAngeles), timeZone: losAngeles) == "2026-03-09 01:30")
        #expect(formatHourMinute(overnight.departureDate(for: springForwardDay, timeZone: losAngeles), timeZone: losAngeles) == "2026-03-09 01:31")
    }

    @Test func `Arrival and departure dates on Fall Back DST day do not shift backward an hour`() throws {
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let fallBackDay = try makeGregorianDate(year: 2026, month: 11, day: 1, timeZone: losAngeles)

        // 2026-11-01 is a 25-hour day in America/Los_Angeles (01:59 PDT -> 01:00 PST).
        // Per GTFS, times are measured from local noon minus 12h so 08:45 stays 08:45 PST.
        let morning = try makeStopTime(arrivalTime: 31_500, departureTime: 31_560)
        #expect(formatHourMinute(morning.arrivalDate(for: fallBackDay, timeZone: losAngeles), timeZone: losAngeles) == "2026-11-01 08:45")
        #expect(formatHourMinute(morning.departureDate(for: fallBackDay, timeZone: losAngeles), timeZone: losAngeles) == "2026-11-01 08:46")

        let overnight = try makeStopTime(arrivalTime: 91_800, departureTime: 91_860) // 25:30 / 25:31
        #expect(formatHourMinute(overnight.arrivalDate(for: fallBackDay, timeZone: losAngeles), timeZone: losAngeles) == "2026-11-02 01:30")
        #expect(formatHourMinute(overnight.departureDate(for: fallBackDay, timeZone: losAngeles), timeZone: losAngeles) == "2026-11-02 01:31")
    }

    @Test func `Arrival and departure dates handle midnight DST transitions`() throws {
        // America/Havana springs forward at midnight on 2026-03-08 (00:00 does not exist).
        let havana = try #require(TimeZone(identifier: "America/Havana"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = havana
        let springForwardStart = calendar.startOfDay(for: try makeGregorianDate(year: 2026, month: 3, day: 8, hour: 12, timeZone: havana))

        let morning = try makeStopTime(arrivalTime: 31_500, departureTime: 31_560)
        #expect(formatHourMinute(morning.arrivalDate(for: springForwardStart, timeZone: havana), timeZone: havana) == "2026-03-08 08:45")
        #expect(formatHourMinute(morning.departureDate(for: springForwardStart, timeZone: havana), timeZone: havana) == "2026-03-08 08:46")
    }
}
