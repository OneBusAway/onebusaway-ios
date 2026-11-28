//
//  BookmarkControlCatalogTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

/// The lookups behind the widget extension's Bookmark control.
@Suite(.serialized)
@MainActor
struct BookmarkControlCatalogTests {
    private let region = Fixtures.pugetSoundRegion.regionIdentifier

    private func stopBookmark(_ name: String, regionIdentifier: Int? = nil) throws -> Bookmark {
        let stop = try #require(try Fixtures.loadSomeStops().first)
        return Bookmark(name: name, regionIdentifier: regionIdentifier ?? region, stop: stop)
    }

    private func tripBookmark(_ name: String) throws -> Bookmark {
        let arrivals = try Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: "arrivals-and-departures-for-stop-1_10914.json")
        let arrivalDeparture = try #require(arrivals.arrivalsAndDepartures.first)
        return Bookmark(name: name, regionIdentifier: region, arrivalDeparture: arrivalDeparture)
    }

    // MARK: - Offered bookmarks

    /// The control only opens a stop, so trip bookmarks work as well as stop
    /// bookmarks (unlike Track Bookmark, which needs a trip).
    @Test func `Offers stop and trip bookmarks in stored order`() throws {
        let stop = try stopBookmark("Home stop")
        let trip = try tripBookmark("49 to Downtown")

        let offered = BookmarkControlCatalog.bookmarks(from: [trip, stop], regionIdentifier: region)

        #expect(offered.map(\.id) == [trip.id, stop.id])
    }

    /// The app can only open a stop in the region it is in.
    @Test func `Skips bookmarks from other regions`() throws {
        let local = try stopBookmark("Local")
        let other = try stopBookmark("Elsewhere", regionIdentifier: region + 1)

        let offered = BookmarkControlCatalog.bookmarks(from: [local, other], regionIdentifier: region)

        #expect(offered.map(\.id) == [local.id])
    }

    @Test func `Offers nothing before a region is known`() throws {
        let bookmark = try stopBookmark("Home stop")

        #expect(BookmarkControlCatalog.bookmarks(from: [bookmark], regionIdentifier: nil).isEmpty)
    }

    // MARK: - Lookup by ID

    /// Keeps the order asked, and drops a bookmark deleted since the control
    /// was set up, so the control falls back to its placeholder.
    @Test func `Looks up bookmarks by ID and drops missing ones`() throws {
        let first = try stopBookmark("First")
        let second = try stopBookmark("Second")
        let deletedID = UUID()

        let found = BookmarkControlCatalog.bookmarks(for: [second.id, deletedID, first.id], from: [first, second], regionIdentifier: region)

        #expect(found.map(\.id) == [second.id, first.id])
    }

    /// After a region switch, a control set to the old region's bookmark must
    /// not open a stop the app can't show.
    @Test func `Lookup by ID skips a bookmark from another region`() throws {
        let other = try stopBookmark("Elsewhere", regionIdentifier: region + 1)

        let found = BookmarkControlCatalog.bookmarks(for: [other.id], from: [other], regionIdentifier: region)

        #expect(found.isEmpty)
    }

    // MARK: - Search

    @Test func `Search matches bookmark name and stop name`() throws {
        let home = try stopBookmark("Home")
        let work = try stopBookmark("Work")
        let stopName = home.stop.name

        let byName = BookmarkControlCatalog.bookmarks(matching: "hom", from: [home, work], regionIdentifier: region)
        #expect(byName.map(\.id) == [home.id])

        let byStop = BookmarkControlCatalog.bookmarks(matching: stopName, from: [home, work], regionIdentifier: region)
        #expect(byStop.map(\.id) == [home.id, work.id])
    }

    @Test func `Search caps results`() throws {
        let many = try (0..<30).map { try stopBookmark("Stop \($0)") }

        let hits = BookmarkControlCatalog.bookmarks(matching: "Stop", from: many, regionIdentifier: region)

        #expect(hits.count == BookmarkControlCatalog.searchResultLimit)
    }
}
