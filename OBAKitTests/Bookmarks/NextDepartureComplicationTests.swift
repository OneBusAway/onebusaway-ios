//
//  NextDepartureComplicationTests.swift
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

@Suite(.serialized)
struct NextDepartureComplicationTests {

    private let upcomingNow = Date(timeIntervalSinceReferenceDate: Double(Int(Date.timeIntervalSinceReferenceDate)))

    private func seconds(from offset: TimeInterval) -> Int {
        Int(upcomingNow.addingTimeInterval(offset).timeIntervalSinceReferenceDate)
    }

    private func makeBookmark(
        id: UUID = UUID(),
        name: String = "Morning Commute",
        stopID: StopID = "stop_1",
        stopName: String = "4th Ave & Pike St",
        regionIdentifier: Int = 1,
        routeShortName: String? = "550",
        tripHeadsign: String? = "Bellevue",
        isTripBookmark: Bool = true,
        isFavorite: Bool = true
    ) -> NextDepartureComplicationBookmark {
        NextDepartureComplicationBookmark(
            id: id,
            name: name,
            stopID: stopID,
            stopName: stopName,
            regionIdentifier: regionIdentifier,
            routeShortName: routeShortName,
            tripHeadsign: tripHeadsign,
            isTripBookmark: isTripBookmark,
            isFavorite: isFavorite
        )
    }

    private func makeDeparture(
        inSeconds offset: TimeInterval,
        predicted: Bool = true,
        tripID: String = "trip_1"
    ) throws -> ArrivalDeparture {
        let target = seconds(from: offset)
        return try Fixtures.arrivalDeparture(
            predicted: predicted,
            scheduledArrival: target,
            predictedArrival: predicted ? target : nil,
            scheduledDeparture: target,
            predictedDeparture: predicted ? target : nil,
            tripID: tripID
        )
    }

    private func makeArrivalDeparture(
        scheduledArrivalOffset: TimeInterval,
        scheduledDepartureOffset: TimeInterval,
        departureEnabled: Bool = true,
        stopSequence: Int = 5,
        tripID: String = "trip_1"
    ) throws -> ArrivalDeparture {
        let arrivalSec = seconds(from: scheduledArrivalOffset)
        let departureSec = seconds(from: scheduledDepartureOffset)
        let dictionary: [String: Any] = [
            "arrivalEnabled": true,
            "blockTripSequence": 1,
            "departureEnabled": departureEnabled,
            "distanceFromStop": 100.0,
            "lastUpdateTime": arrivalSec,
            "numberOfStopsAway": 1,
            "predicted": false,
            "routeId": "route_1",
            "scheduledArrivalTime": arrivalSec,
            "scheduledDepartureTime": departureSec,
            "serviceDate": arrivalSec,
            "situationIds": [],
            "status": "SCHEDULED",
            "stopId": "stop_1",
            "stopSequence": stopSequence,
            "tripId": tripID,
            "vehicleId": "vehicle_1"
        ]
        return try Fixtures.dictionaryToModel(type: ArrivalDeparture.self, dictionary: dictionary)
    }

    // MARK: - Accessory Family Limits

    @Test func `Accessory widget families request at most one bookmark`() {
        #expect(WidgetBookmarkFamily.accessoryCircular.maximumBookmarks == 1)
        #expect(WidgetBookmarkFamily.accessoryRectangular.maximumBookmarks == 1)
        #expect(WidgetBookmarkFamily.accessoryInline.maximumBookmarks == 1)
        #expect(WidgetBookmarkFamily.systemMedium.maximumBookmarks == 2)
        #expect(WidgetBookmarkFamily.systemLarge.maximumBookmarks == 7)
    }

    // MARK: - Empty & Fallback States

    @Test func `No bookmarks resolves to noBookmarks state`() {
        let state = NextDepartureComplication.resolve(
            bookmarks: [NextDepartureComplicationBookmark](),
            departuresByBookmark: [:],
            now: upcomingNow
        )

        #expect(state == .noBookmarks)
        #expect(state.bookmark == nil)
        #expect(state.departure == nil)
    }

    @Test func `Missing departures entry resolves to unavailable state`() {
        let bookmark = makeBookmark()
        let state = NextDepartureComplication.resolve(
            bookmarks: [bookmark],
            departuresByBookmark: [:],
            now: upcomingNow
        )

        #expect(state == .unavailable(bookmark: bookmark))
        #expect(state.bookmark == bookmark)
        #expect(state.departure == nil)
    }

    @Test func `Empty departures list resolves to noDepartures state`() {
        let bookmark = makeBookmark()
        let state = NextDepartureComplication.resolve(
            bookmarks: [bookmark],
            departuresByBookmark: [bookmark.id: []],
            now: upcomingNow
        )

        #expect(state == .noDepartures(bookmark: bookmark))
        #expect(state.bookmark == bookmark)
        #expect(state.departure == nil)
    }

    @Test func `Past and exact-now departures are ignored and fall back to noDepartures`() throws {
        let bookmark = makeBookmark()
        let past = try makeDeparture(inSeconds: -120, tripID: "past")
        let atNow = try makeDeparture(inSeconds: 0, tripID: "now")

        let state = NextDepartureComplication.resolve(
            bookmarks: [bookmark],
            departuresByBookmark: [bookmark.id: [past, atNow]],
            now: upcomingNow
        )

        #expect(state == .noDepartures(bookmark: bookmark))
    }

    // MARK: - Next Departure Selection & Fallback Metadata

    @Test func `Soonest upcoming departure is selected regardless of input order`() throws {
        let bookmark = makeBookmark(routeShortName: "40", tripHeadsign: "Northgate")
        let past = try makeDeparture(inSeconds: -60, tripID: "past")
        let later = try makeDeparture(inSeconds: 20 * 60, tripID: "later")
        let soonest = try makeDeparture(inSeconds: 5 * 60, tripID: "soonest")

        let state = NextDepartureComplication.resolve(
            bookmarks: [bookmark],
            departuresByBookmark: [bookmark.id: [later, past, soonest]],
            now: upcomingNow
        )

        let resolved = try #require(state.departure)
        #expect(resolved.departureDate == soonest.arrivalDepartureDate)
        #expect(resolved.routeShortName == "40")
        #expect(resolved.headsign == "Northgate")
        #expect(resolved.isRealTime)
        #expect(resolved.stopName == "4th Ave & Pike St")
        #expect(resolved.minutesUntil(at: upcomingNow) == 5)
        #expect(!resolved.isArrivingNow(at: upcomingNow))
    }

    @Test func `Loaded REST arrival provides route badge, headsign, and color`() throws {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        let firstArrival = try #require(stopArrivals.arrivalsAndDepartures.first)
        let referenceNow = firstArrival.arrivalDepartureDate.addingTimeInterval(-8 * 60)

        let bookmark = makeBookmark(
            name: "Campus Stop",
            stopID: firstArrival.stopID,
            stopName: firstArrival.stop.name,
            routeShortName: nil,
            tripHeadsign: nil,
            isTripBookmark: false
        )

        let state = NextDepartureComplication.resolve(
            bookmarks: [bookmark],
            departuresByBookmark: [bookmark.id: stopArrivals.arrivalsAndDepartures],
            now: referenceNow
        )

        let resolved = try #require(state.departure)
        #expect(!resolved.routeShortName.isEmpty)
        #expect(!resolved.headsign.isEmpty)
        #expect(resolved.routeShortName == firstArrival.routeShortName)
        #expect(resolved.headsign == (firstArrival.tripHeadsign ?? firstArrival.stop.name))
    }

    // MARK: - Countdown & Arriving Now

    @Test func `Countdown under sixty seconds reports arriving NOW`() {
        let departure = ComplicationDeparture(
            routeShortName: "10",
            headsign: "Downtown",
            departureDate: upcomingNow.addingTimeInterval(35),
            isRealTime: true,
            scheduleStatus: .onTime,
            stopName: "Pine St",
            bookmarkName: "10 to Downtown"
        )
        let expectedNow = Bundle.obaKitCore.localizedString(forKey: "stop_page.countdown.now", value: "NOW", table: nil)

        #expect(departure.minutesUntil(at: upcomingNow) == 0)
        #expect(departure.isArrivingNow(at: upcomingNow))
        #expect(departure.shortCountdownText(at: upcomingNow) == expectedNow)
        #expect(departure.countdownSnapshot(at: upcomingNow, locale: Locale(identifier: "en_US")) == expectedNow)
    }

    @Test func `Countdown multiple minutes out formats compact minute snapshot`() {
        let departure = ComplicationDeparture(
            routeShortName: "C Line",
            headsign: "South Lake Union",
            departureDate: upcomingNow.addingTimeInterval(8 * 60 + 30),
            isRealTime: true,
            scheduleStatus: .delayed,
            stopName: "3rd Ave",
            bookmarkName: "C Line"
        )
        let shortFmt = Bundle.obaKitCore.localizedString(forKey: "formatters.short_time_fmt", value: "%dm", table: nil)
        let expectedLocalizedShort = String(format: shortFmt, 8)

        #expect(departure.minutesUntil(at: upcomingNow) == 8)
        #expect(!departure.isArrivingNow(at: upcomingNow))
        #expect(departure.shortCountdownText(at: upcomingNow) == expectedLocalizedShort)
        #expect(departure.countdownSnapshot(at: upcomingNow, locale: Locale(identifier: "en_US")) == "8m")
    }

    // MARK: - Inline Summary

    @Test func `Inline summary formats departure and fallback states`() {
        let bookmark = makeBookmark(name: "Pike & 4th", routeShortName: "550", isTripBookmark: true)
        let departure = ComplicationDeparture(
            routeShortName: "550",
            headsign: "Bellevue",
            departureDate: upcomingNow.addingTimeInterval(7 * 60 + 20),
            isRealTime: true,
            scheduleStatus: .onTime,
            stopName: "4th Ave & Pike St",
            bookmarkName: "Morning Commute"
        )
        let enUS = Locale(identifier: "en_US")

        #expect(
            NextDepartureComplication.inlineSummary(
                for: .departure(departure, bookmark: bookmark),
                now: upcomingNow,
                noBookmarksText: "No bookmarks",
                noDeparturesText: "No departures",
                unavailableText: "Unavailable",
                locale: enUS
            ) == "550 · 7m · Bellevue"
        )
        #expect(
            NextDepartureComplication.inlineSummary(
                for: .noDepartures(bookmark: bookmark),
                now: upcomingNow,
                noBookmarksText: "No bookmarks",
                noDeparturesText: "No departures",
                unavailableText: "Unavailable",
                locale: enUS
            ) == "550 · No departures"
        )
        #expect(
            NextDepartureComplication.inlineSummary(
                for: .unavailable(bookmark: bookmark),
                now: upcomingNow,
                noBookmarksText: "No bookmarks",
                noDeparturesText: "No departures",
                unavailableText: "Unavailable",
                locale: enUS
            ) == "550 · Unavailable"
        )
        #expect(
            NextDepartureComplication.inlineSummary(
                for: .noBookmarks,
                now: upcomingNow,
                noBookmarksText: "No bookmarks",
                noDeparturesText: "No departures",
                unavailableText: "Unavailable",
                locale: enUS
            ) == "No bookmarks"
        )
    }

    // MARK: - Watch Bookmark Selection

    @Test func `Top watch bookmark prefers first favorited bookmark in current region`() {
        let otherRegion = WatchBookmark(
            id: UUID(),
            name: "Other Region",
            regionIdentifier: 2,
            stopID: "2_100",
            stopName: "Other Stop",
            latitude: 0,
            longitude: 0,
            isFavorite: true
        )
        let unfavorited = WatchBookmark(
            id: UUID(),
            name: "Unfavorited",
            regionIdentifier: 1,
            stopID: "1_100",
            stopName: "First Stop",
            latitude: 0,
            longitude: 0,
            isFavorite: false
        )
        let favorite = WatchBookmark(
            id: UUID(),
            name: "Favorite",
            regionIdentifier: 1,
            stopID: "1_200",
            stopName: "Second Stop",
            latitude: 0,
            longitude: 0,
            isFavorite: true,
            routeID: "1_10",
            routeShortName: "10",
            tripHeadsign: "Capitol Hill"
        )

        let chosen = NextDepartureComplication.topBookmark(
            from: [otherRegion, unfavorited, favorite],
            regionIdentifier: 1
        )
        #expect(chosen?.id == favorite.id)

        let fallback = NextDepartureComplication.topBookmark(
            from: [otherRegion, unfavorited],
            regionIdentifier: 1
        )
        #expect(fallback?.id == unfavorited.id)

        #expect(NextDepartureComplication.topBookmark(from: [otherRegion], regionIdentifier: 1) == nil)
    }

    // MARK: - Timeline Boundary Progression

    @Test func `Complication advances cleanly across WidgetTimelinePlanner boundaries`() throws {
        let bookmark = makeBookmark(routeShortName: "8", tripHeadsign: "Seattle Center")
        let first = try makeDeparture(inSeconds: 8 * 60, tripID: "trip_8")
        let second = try makeDeparture(inSeconds: 20 * 60, tripID: "trip_20")
        let departures = [first, second]

        let plan = WidgetTimelinePlanner().plan(
            departureDates: departures.map(\.arrivalDepartureDate),
            now: upcomingNow
        )

        #expect(plan.entryDates == [upcomingNow, first.arrivalDepartureDate, second.arrivalDepartureDate])

        let entry0State = NextDepartureComplication.resolve(
            bookmarks: [bookmark],
            departuresByBookmark: [bookmark.id: WidgetTimelinePlanner.departures(departures, visibleAt: plan.entryDates[0])],
            now: plan.entryDates[0]
        )
        #expect(entry0State.departure?.departureDate == first.arrivalDepartureDate)

        let entry1State = NextDepartureComplication.resolve(
            bookmarks: [bookmark],
            departuresByBookmark: [bookmark.id: WidgetTimelinePlanner.departures(departures, visibleAt: plan.entryDates[1])],
            now: plan.entryDates[1]
        )
        #expect(entry1State.departure?.departureDate == second.arrivalDepartureDate)

        let entry2State = NextDepartureComplication.resolve(
            bookmarks: [bookmark],
            departuresByBookmark: [bookmark.id: WidgetTimelinePlanner.boardableDepartures(departures, visibleAt: plan.entryDates[2])],
            now: plan.entryDates[2]
        )
        #expect(entry2State == .noDepartures(bookmark: bookmark))
    }

    // MARK: - Boardable Vehicles, Layovers, Zero Spacing & Accessibility

    @Test func `Arrival-only vehicles are ignored and layover stops use departure timestamp`() throws {
        let bookmark = makeBookmark(routeShortName: "40", tripHeadsign: "Northgate")
        let arrivalOnly = try makeArrivalDeparture(
            scheduledArrivalOffset: 2 * 60,
            scheduledDepartureOffset: 2 * 60,
            departureEnabled: false,
            tripID: "arrival_only"
        )
        let layover = try makeArrivalDeparture(
            scheduledArrivalOffset: -60,
            scheduledDepartureOffset: 4 * 60,
            departureEnabled: true,
            stopSequence: 5,
            tripID: "layover"
        )

        let state = NextDepartureComplication.resolve(
            bookmarks: [bookmark],
            departuresByBookmark: [bookmark.id: [arrivalOnly, layover]],
            now: upcomingNow
        )

        let resolved = try #require(state.departure)
        #expect(resolved.departureDate == layover.departureDate)
        #expect(resolved.minutesUntil(at: upcomingNow) == 4)

        let visible = WidgetTimelinePlanner.boardableDepartures([arrivalOnly, layover], visibleAt: upcomingNow)
        #expect(visible.map(\.tripID) == ["layover"])
    }

    @Test func `Single-bookmark complication planner emits zero-spaced entries for all departures within 30 minutes`() {
        // 14 departures spaced 2 minutes apart inside the 30-minute reload window.
        let departureDates = (1...14).map { upcomingNow.addingTimeInterval(Double($0) * 2 * 60) }
        let plan = WidgetTimelinePlanner.singleBookmarkComplication().plan(departureDates: departureDates, now: upcomingNow)

        #expect(plan.entryDates == [upcomingNow] + departureDates)
        #expect(plan.reloadDate == upcomingNow.addingTimeInterval(30 * 60))
    }

    @Test func `Fallback watch bookmark preserves synced bookmark when region is unavailable`() {
        let unfavorited = WatchBookmark(
            id: UUID(),
            name: "First",
            regionIdentifier: 1,
            stopID: "1_1",
            stopName: "Stop 1",
            latitude: 0,
            longitude: 0,
            isFavorite: false
        )
        let favorite = WatchBookmark(
            id: UUID(),
            name: "Fav",
            regionIdentifier: 2,
            stopID: "2_1",
            stopName: "Stop 2",
            latitude: 0,
            longitude: 0,
            isFavorite: true
        )

        #expect(NextDepartureComplication.fallbackBookmark(from: [unfavorited, favorite])?.id == favorite.id)
        #expect(NextDepartureComplication.fallbackBookmark(from: [unfavorited])?.id == unfavorited.id)
        #expect(NextDepartureComplication.fallbackBookmark(from: []) == nil)

        // When region lookup fails but a fallback bookmark is preserved with empty departures dict,
        // the complication state resolves to .unavailable rather than .noBookmarks.
        let state = NextDepartureComplication.resolve(
            watchBookmarks: [favorite],
            departuresByBookmark: [:],
            now: upcomingNow
        )
        #expect(state == .unavailable(bookmark: NextDepartureComplicationBookmark(watchBookmark: favorite)))
    }

    @Test func `Spoken accessibility label includes stop name and formatted departure clock time`() {
        let departureDate = upcomingNow.addingTimeInterval(6 * 60)
        let formatters = Formatters(
            locale: Locale(identifier: "en_US"),
            calendar: Calendar(identifier: .gregorian),
            themeColors: ThemeColors.shared
        )
        let departure = ComplicationDeparture(
            routeShortName: "550",
            headsign: "Bellevue",
            departureDate: departureDate,
            isRealTime: true,
            scheduleStatus: .onTime,
            stopName: "4th Ave & Pike St",
            bookmarkName: "Morning Commute"
        )

        let label = departure.spokenAccessibilityLabel(
            at: upcomingNow,
            formatters: formatters,
            locale: Locale(identifier: "en_US")
        )
        let expectedTime = formatters.timeFormatter.string(from: departureDate)
        #expect(label.contains("550 Bellevue"))
        #expect(label.contains("in 6 minutes"))
        #expect(label.contains(expectedTime))
        #expect(label.contains("4th Ave & Pike St"))
    }
}
