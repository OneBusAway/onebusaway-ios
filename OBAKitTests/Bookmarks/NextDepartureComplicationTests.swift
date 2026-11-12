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
import SwiftUI
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
    }

    // MARK: - Inline Presentation

    @Test func `Inline departure text renders route, ticking countdown, and headsign`() {
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
        let snapshot = ComplicationPresentation.inlineDepartureSnapshot(
            for: departure,
            at: upcomingNow,
            locale: enUS
        )

        #expect(snapshot.contains("550"))
        #expect(snapshot.contains("7m"))
        #expect(snapshot.contains("Bellevue"))
    }

    // MARK: - Timeline Boundary Progression

    @Test func `Complication advances cleanly across single-bookmark planner boundaries including NOW`() throws {
        let bookmark = makeBookmark(routeShortName: "8", tripHeadsign: "Seattle Center")
        let first = try makeDeparture(inSeconds: 8 * 60, tripID: "trip_8")
        let second = try makeDeparture(inSeconds: 20 * 60, tripID: "trip_20")
        let departures = [first, second]
        let expectedNow = Bundle.obaKitCore.localizedString(forKey: "stop_page.countdown.now", value: "NOW", table: nil)

        let plan = WidgetTimelinePlanner.singleBookmarkComplication().plan(
            departureDates: departures.map(\.departureDate),
            now: upcomingNow
        )

        #expect(plan.entryDates == [
            upcomingNow,
            first.departureDate.addingTimeInterval(-59),
            first.departureDate,
            second.departureDate.addingTimeInterval(-59),
            second.departureDate
        ])

        let entry0State = NextDepartureComplication.resolve(
            bookmarks: [bookmark],
            departuresByBookmark: [bookmark.id: WidgetTimelinePlanner.boardableDepartures(departures, visibleAt: plan.entryDates[0])],
            now: plan.entryDates[0]
        )
        let entry0Departure = try #require(entry0State.departure)
        #expect(entry0Departure.departureDate == first.departureDate)
        #expect(!entry0Departure.isArrivingNow(at: plan.entryDates[0]))

        let nowEntryState = NextDepartureComplication.resolve(
            bookmarks: [bookmark],
            departuresByBookmark: [bookmark.id: WidgetTimelinePlanner.boardableDepartures(departures, visibleAt: plan.entryDates[1])],
            now: plan.entryDates[1]
        )
        let nowDeparture = try #require(nowEntryState.departure)
        #expect(nowDeparture.departureDate == first.departureDate)
        #expect(nowDeparture.isArrivingNow(at: plan.entryDates[1]))
        #expect(nowDeparture.shortCountdownText(at: plan.entryDates[1]) == expectedNow)

        let entry2State = NextDepartureComplication.resolve(
            bookmarks: [bookmark],
            departuresByBookmark: [bookmark.id: WidgetTimelinePlanner.boardableDepartures(departures, visibleAt: plan.entryDates[2])],
            now: plan.entryDates[2]
        )
        #expect(entry2State.departure?.departureDate == second.departureDate)

        let finalState = NextDepartureComplication.resolve(
            bookmarks: [bookmark],
            departuresByBookmark: [bookmark.id: WidgetTimelinePlanner.boardableDepartures(departures, visibleAt: plan.entryDates[4])],
            now: plan.entryDates[4]
        )
        #expect(finalState == .noDepartures(bookmark: bookmark))
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

        let expectedBoundaries = departureDates.flatMap { [$0.addingTimeInterval(-59), $0] }
        #expect(plan.entryDates == [upcomingNow] + expectedBoundaries)
        #expect(plan.reloadDate == upcomingNow.addingTimeInterval(30 * 60))
    }

    @Test func `Departure accessibility label renders formatted departure details`() {
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

        let snapshot = ComplicationPresentation.departureAccessibilitySnapshot(
            for: departure,
            formatters: formatters,
            at: upcomingNow,
            locale: Locale(identifier: "en_US")
        )

        #expect(snapshot.contains("550"))
        #expect(snapshot.contains("Bellevue"))
        #expect(snapshot.contains("6 minutes"))
    }

    // One composite preview keeps the reviewer screenshot's standard, NOW,
    // and reduced-luminance states together for visual comparison.
    // swiftlint:disable function_body_length
    @Test @MainActor
    func `Render complication snapshots for Lock Screen and Always-On`() throws {
        let departure = ComplicationDeparture(
            routeShortName: "550",
            headsign: "Bellevue",
            departureDate: upcomingNow.addingTimeInterval(8 * 60),
            isRealTime: true,
            scheduleStatus: .onTime,
            stopName: "4th Ave & Pike St",
            bookmarkName: "Morning Commute"
        )
        let formatters = Formatters(
            locale: Locale(identifier: "en_US"),
            calendar: Calendar(identifier: .gregorian),
            themeColors: ThemeColors.shared
        )

        let nowDeparture = ComplicationDeparture(
            routeShortName: "550",
            headsign: "Bellevue",
            departureDate: upcomingNow.addingTimeInterval(30),
            isRealTime: true,
            scheduleStatus: .onTime,
            stopName: "4th Ave & Pike St",
            bookmarkName: "Morning Commute"
        )

        let previewView = VStack(alignment: .leading, spacing: 16) {
            Text("Lock Screen Accessory Widgets").font(.headline).foregroundStyle(.white)

            Text("Standard Luminance (8m away)").font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 20) {
                ZStack {
                    Circle().fill(Color.gray.opacity(0.3)).frame(width: 60, height: 60)
                    ComplicationCircularDepartureContent(departure: departure, referenceDate: upcomingNow, formatters: formatters, isFullColor: false)
                }
                ComplicationRectangularDepartureContent(departure: departure, referenceDate: upcomingNow, formatters: formatters, isFullColor: false)
                    .frame(width: 160)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.3)))
            }
            HStack {
                ComplicationPresentation.inlineDepartureText(for: departure, at: upcomingNow, locale: Locale(identifier: "en_US"))
                    .foregroundStyle(.white)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.3)))

            Divider().background(Color.gray)

            Text("Arriving Under 1 Minute (NOW)").font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 20) {
                ZStack {
                    Circle().fill(Color.gray.opacity(0.3)).frame(width: 60, height: 60)
                    ComplicationCircularDepartureContent(departure: nowDeparture, referenceDate: upcomingNow, formatters: formatters, isFullColor: false)
                }
                ComplicationRectangularDepartureContent(departure: nowDeparture, referenceDate: upcomingNow, formatters: formatters, isFullColor: false)
                    .frame(width: 160)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.3)))
            }
            HStack {
                ComplicationPresentation.inlineDepartureText(for: nowDeparture, at: upcomingNow, locale: Locale(identifier: "en_US"))
                    .foregroundStyle(.white)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.3)))

            Divider().background(Color.gray)

            Text("Always-On (Reduced Luminance)").font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 20) {
                ZStack {
                    Circle().fill(Color.gray.opacity(0.2)).frame(width: 60, height: 60)
                    VStack(spacing: 1) {
                        Text(verbatim: departure.routeShortName)
                            .font(.system(.caption2, design: .rounded, weight: .heavy))
                        Text(verbatim: TickingCountdownText.snapshot(
                            departure: departure.departureDate,
                            now: upcomingNow,
                            locale: Locale(identifier: "en_US")
                        ))
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(.gray)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        ComplicationRouteBadge(
                            routeShortName: departure.routeShortName,
                            routeColorHex: departure.routeColorHex,
                            routeTextColorHex: departure.routeTextColorHex,
                            isFullColor: false
                        )
                        Spacer(minLength: 4)
                        Text(verbatim: TickingCountdownText.snapshot(
                            departure: departure.departureDate,
                            now: upcomingNow,
                            locale: Locale(identifier: "en_US")
                        ))
                            .font(.system(.headline, design: .rounded, weight: .heavy))
                            .monospacedDigit()
                    }
                    Text(verbatim: departure.headsign)
                        .font(.subheadline.weight(.semibold))
                    Text(verbatim: "\(formatters.timeFormatter.string(from: departure.departureDate)) · \(departure.stopName)")
                        .font(.caption2)
                }
                .foregroundStyle(.gray)
                .frame(width: 160, alignment: .leading)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.2)))
            }
            HStack {
                Text(verbatim: ComplicationPresentation.inlineDepartureSnapshot(
                    for: departure,
                    at: upcomingNow,
                    locale: Locale(identifier: "en_US")
                ))
                    .foregroundStyle(.gray)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.2)))
        }
        .padding(20)
        .background(Color.black)
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: previewView)
        renderer.scale = 2.0
        let uiImage = try #require(renderer.uiImage)
        let data = try #require(uiImage.pngData())
        #expect(uiImage.size.width > 0)
        #expect(uiImage.size.height > 0)

        let outputURL = ProcessInfo.processInfo.environment["OBA_COMPLICATION_PREVIEW_OUTPUT"]
            .map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("complication_preview_all.png")
        try data.write(to: outputURL)
        #expect(FileManager.default.fileExists(atPath: outputURL.path))
    }
    // swiftlint:enable function_body_length
}
