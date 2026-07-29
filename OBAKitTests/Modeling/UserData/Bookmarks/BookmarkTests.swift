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
