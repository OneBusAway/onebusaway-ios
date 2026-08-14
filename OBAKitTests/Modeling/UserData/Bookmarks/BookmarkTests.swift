//
//  BookmarkTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import CoreLocation
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try

@Suite(.serialized)
final class BookmarkTests: OBATestCase {

    var region: Region!
    var stops: [Stop]!

    override init() async throws {
        try await super.init()

        region = try! Fixtures.loadSomeRegions()[1]
        stops = try! Fixtures.loadSomeStops()
    }

    @Test func creation() {
        let stop = stops[0]
        let bookmark = Bookmark(name: "BM 1", regionIdentifier: region.regionIdentifier, stop: stop)
        #expect(bookmark.name == "BM 1")
        #expect(bookmark.regionIdentifier == region.regionIdentifier)
        #expect(bookmark.stopID == stop.id)
        #expect(bookmark.stop == stop)
    }

    @Test func `Codable roundtripping`() {
        let stop = stops[0]
        let bookmark = Bookmark(name: "BM 1", regionIdentifier: region.regionIdentifier, stop: stop)
        let roundtripped = try! Fixtures.roundtripCodable(type: Bookmark.self, model: bookmark)
        #expect(roundtripped.name == "BM 1")
        #expect(roundtripped.regionIdentifier == region.regionIdentifier)
        #expect(roundtripped.stopID == stop.id)
        #expect(roundtripped.stop == stop)
    }

    /// `dateCreated` survives the store's encoder, since the home sheet's
    /// most-recent-first ordering reads it back off persisted bookmarks.
    @Test func `Codable roundtripping preserves dateCreated`() {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let bookmark = Bookmark(
            name: "BM 1",
            regionIdentifier: region.regionIdentifier,
            stop: stops[0],
            dateCreated: created
        )

        let roundtripped = try! Fixtures.roundtripCodable(type: Bookmark.self, model: bookmark)

        #expect(roundtripped.dateCreated.timeIntervalSince1970 == created.timeIntervalSince1970)
    }

    /// Bookmarks written before `dateCreated` existed have no such key. They must
    /// decode as `.distantPast` rather than throwing or defaulting to "now" —
    /// "now" would make every stored bookmark look freshly created on the first
    /// launch after upgrading and scramble most-recent-first ordering.
    @Test func `Decoding a bookmark saved without dateCreated yields distantPast`() throws {
        let bookmark = Bookmark(name: "BM 1", regionIdentifier: region.regionIdentifier, stop: stops[0])

        // Encode, then strip the key to reproduce a pre-upgrade payload.
        let encoded = try PropertyListEncoder().encode(bookmark)
        var plist = try #require(
            try PropertyListSerialization.propertyList(from: encoded, format: nil) as? [String: Any]
        )
        try #require(plist.removeValue(forKey: "dateCreated") != nil, "Expected dateCreated in the encoded form")

        let legacy = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        let decoded = try PropertyListDecoder().decode(Bookmark.self, from: legacy)

        #expect(decoded.dateCreated == .distantPast)
        #expect(decoded.id == bookmark.id)
        #expect(decoded.name == "BM 1")
    }

    /// Pinning is persisted state, so it has to survive the store's encoder.
    @Test func `Codable roundtripping preserves isPinned`() {
        let bookmark = Bookmark(name: "BM 1", regionIdentifier: region.regionIdentifier, stop: stops[0])
        #expect(bookmark.isPinned == false, "New bookmarks start unpinned")

        bookmark.isPinned = true
        let roundtripped = try! Fixtures.roundtripCodable(type: Bookmark.self, model: bookmark)

        #expect(roundtripped.isPinned)
    }

    /// Bookmarks written before pinning existed have no `isPinned` key. Nothing
    /// was pinned then, so `false` is the truthful default — and decoding must
    /// not throw.
    @Test func `Decoding a bookmark saved without isPinned yields false`() throws {
        let bookmark = Bookmark(name: "BM 1", regionIdentifier: region.regionIdentifier, stop: stops[0])
        bookmark.isPinned = true

        let encoded = try PropertyListEncoder().encode(bookmark)
        var plist = try #require(
            try PropertyListSerialization.propertyList(from: encoded, format: nil) as? [String: Any]
        )
        try #require(plist.removeValue(forKey: "isPinned") != nil, "Expected isPinned in the encoded form")

        let legacy = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        let decoded = try PropertyListDecoder().decode(Bookmark.self, from: legacy)

        #expect(decoded.isPinned == false)
        #expect(decoded.id == bookmark.id)
    }

    @Test func `Updating stop property with right stop`() {
        let bookmark = Bookmark(name: "BM 1", regionIdentifier: region.regionIdentifier, stop: stops[0])
        #expect(bookmark.stop.routes.count > 1)
        let stop = stops[0]
        stop.routes = []
        bookmark.stop = stop

        #expect(bookmark.stop.routes.count == 0)
    }

    @Test func `Updating stop property with wrong stop`() {
        let bookmark = Bookmark(name: "BM 1", regionIdentifier: region.regionIdentifier, stop: stops[0])
        bookmark.stop = stops[1]

        #expect(bookmark.stop.id == stops[0].id)
    }
}
