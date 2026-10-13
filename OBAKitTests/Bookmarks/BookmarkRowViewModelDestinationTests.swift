//
//  BookmarkRowViewModelDestinationTests.swift
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

/// How a destination bookmark's row combines departures with what is known
/// about each one reaching the destination (#1080).
@Suite(.serialized)
final class BookmarkRowViewModelDestinationTests: OBATestCase {

    private func makeBookmark(destination: Bool) throws -> Bookmark {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        let arrivalDeparture = try #require(stopArrivals.arrivalsAndDepartures.first)
        let destinationStop = try #require(try Fixtures.loadSomeStops().first)
        return Bookmark(
            name: "Commute",
            regionIdentifier: pugetSoundRegionIdentifier,
            arrivalDeparture: arrivalDeparture,
            destinationStop: destination ? destinationStop : nil
        )
    }

    private func departure(_ tripID: String) throws -> ArrivalDeparture {
        try Fixtures.arrivalDeparture(tripID: tripID)
    }

    private let arrival = DestinationArrival(
        arrivalDate: Date(timeIntervalSinceReferenceDate: 1_700_001_000),
        scheduledArrivalDate: Date(timeIntervalSinceReferenceDate: 1_700_000_900),
        isRealTime: true
    )

    @Test func `Departures that do not reach the destination are dropped`() throws {
        let bookmark = try makeBookmark(destination: true)
        let shortTurn = try departure("short_turn")
        let fullRun = try departure("full_run")
        let lookups: [TripIdentifier: DestinationArrivalLookup] = ["short_turn": .notServed, "full_run": .arrives(arrival)]

        let row = BookmarkRowViewModel(
            bookmark: bookmark,
            arrivalDepartures: [shortTurn, fullRun],
            highlightedTripIDs: [],
            destinationLookup: { lookups[$0.tripID] ?? .pending }
        )

        #expect(row.arrivalDepartures.map(\.tripID) == ["full_run"])
        #expect(row.destinationStatus == .arrives(arrival))
        #expect(row.destinationStopName == bookmark.destinationStopName)
    }

    @Test func `When no departure reaches the destination the row says so`() throws {
        let bookmark = try makeBookmark(destination: true)

        let row = BookmarkRowViewModel(
            bookmark: bookmark,
            arrivalDepartures: [try departure("a"), try departure("b")],
            highlightedTripIDs: [],
            destinationLookup: { _ in .notServed }
        )

        #expect(row.arrivalDepartures.isEmpty)
        #expect(row.destinationStatus == .notServed)
    }

    @Test func `A departure whose schedule has not loaded shows the arrival as loading`() throws {
        let bookmark = try makeBookmark(destination: true)

        let row = BookmarkRowViewModel(
            bookmark: bookmark,
            arrivalDepartures: [try departure("a")],
            highlightedTripIDs: [],
            destinationLookup: { _ in .pending }
        )

        #expect(row.arrivalDepartures.count == 1)
        #expect(row.destinationStatus == .loading)
    }

    /// With no departures at all the card already says "No upcoming
    /// departures"; it must not also claim the destination isn't served.
    /// A schedule that can't be loaded must not leave the card on "Loading…".
    /// The departure itself is still good, so it stays; only the arrival line goes.
    @Test func `A departure whose schedule failed to load keeps its departure and hides the arrival`() throws {
        let bookmark = try makeBookmark(destination: true)

        let row = BookmarkRowViewModel(
            bookmark: bookmark,
            arrivalDepartures: [try departure("a")],
            highlightedTripIDs: [],
            destinationLookup: { _ in .unavailable }
        )

        #expect(row.arrivalDepartures.count == 1)
        #expect(row.destinationStatus == nil)
    }

    @Test func `No departures means no destination status`() throws {
        let bookmark = try makeBookmark(destination: true)

        let row = BookmarkRowViewModel(
            bookmark: bookmark,
            arrivalDepartures: [],
            highlightedTripIDs: [],
            destinationLookup: { _ in .notServed }
        )

        #expect(row.destinationStatus == nil)
    }

    @Test func `A trip bookmark without a destination is unaffected`() throws {
        let bookmark = try makeBookmark(destination: false)

        let row = BookmarkRowViewModel(
            bookmark: bookmark,
            arrivalDepartures: [try departure("a")],
            highlightedTripIDs: [],
            destinationLookup: { _ in .notServed }
        )

        #expect(row.arrivalDepartures.count == 1)
        #expect(row.destinationStatus == nil)
        #expect(row.destinationStopName == nil)
    }

    @Test @MainActor func `Destination text describes each state`() throws {
        let bookmark = try makeBookmark(destination: true)
        let name = try #require(bookmark.destinationStopName)
        let formatters = Formatters(locale: Locale(identifier: "en_US"), calendar: Calendar.current, themeColors: ThemeColors.shared)

        func text(_ lookup: DestinationArrivalLookup) throws -> String? {
            let row = BookmarkRowViewModel(
                bookmark: bookmark,
                arrivalDepartures: [try departure("a")],
                highlightedTripIDs: [],
                destinationLookup: { _ in lookup }
            )
            return formatters.destinationText(for: row)
        }

        let time = formatters.timeFormatter.string(from: arrival.arrivalDate)
        #expect(try text(.arrives(arrival)) == "Arrives \(name) at \(time)")
        #expect(try text(.pending) == "Loading arrival at \(name)…")
        #expect(try text(.notServed) == "Upcoming trips don't stop at \(name)")

        let scheduled = DestinationArrival(arrivalDate: arrival.scheduledArrivalDate, scheduledArrivalDate: arrival.scheduledArrivalDate, isRealTime: false)
        let scheduledTime = formatters.timeFormatter.string(from: scheduled.arrivalDate)
        #expect(try text(.arrives(scheduled)) == "Arrives \(name) at \(scheduledTime) (scheduled)")
    }
}
