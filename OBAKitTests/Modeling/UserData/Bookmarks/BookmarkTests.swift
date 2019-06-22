//
//  BookmarkTests.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 6/22/19.
//

import XCTest
import Nimble
import OHHTTPStubs
import CoreLocation
@testable import OBAKit

// swiftlint:disable force_try

class BookmarkTests: OBATestCase {

    var region: Region!
    var stops: [Stop]!

    override func setUp() {
        super.setUp()

        region = try! loadSomeRegions()[1]
        stops = try! loadSomeStops()
    }

    func testCreation() {
        let stop = stops[0]
        let bookmark = Bookmark(name: "BM 1", regionIdentifier: region.regionIdentifier, stop: stop)
        expect(bookmark.name) == "BM 1"
        expect(bookmark.regionIdentifier) == region.regionIdentifier
        expect(bookmark.stopID) == stop.id
        expect(bookmark.stop) == stop
    }

    func testCodableRoundtripping() {
        let stop = stops[0]
        let bookmark = Bookmark(name: "BM 1", regionIdentifier: region.regionIdentifier, stop: stop)
        let roundtripped = try! roundtripCodable(type: Bookmark.self, model: bookmark)
        expect(roundtripped.name) == "BM 1"
        expect(roundtripped.regionIdentifier) == region.regionIdentifier
        expect(roundtripped.stopID) == stop.id
        expect(roundtripped.stop) == stop
    }

    func testUpdatingStopPropertyWithRightStop() {
        let bookmark = Bookmark(name: "BM 1", regionIdentifier: region.regionIdentifier, stop: stops[0])
        expect(bookmark.stop.routes.count).to(beGreaterThan(1))
        let stop = stops[0]
        stop.routes = []
        bookmark.stop = stop

        expect(bookmark.stop.routes.count) == 0
    }

    func testUpdatingStopPropertyWithWrongStop() {
        let bookmark = Bookmark(name: "BM 1", regionIdentifier: region.regionIdentifier, stop: stops[0])
        bookmark.stop = stops[1]

        expect(bookmark.stop.id) == stops[0].id
    }
}
