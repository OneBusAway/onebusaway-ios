//
//  GeohashCacheTests.swift
//  OBAKitTests
//
//  Created by Alan Chu on 4/10/23.
//

import XCTest
@testable import OBAKitCore

final class GeohashCacheTests: XCTestCase {
    var seattle: Geohash!
    var bellevue: Geohash!

    let expectedSeattleElements: [String] = ["Hello", "Seattle!"]
    let expectedBellevueElements: [String] = ["Hey", "Bellevue!"]

    override func setUp() async throws {
        seattle = try XCTUnwrap(Geohash(geohash: "c23nb"))
        bellevue = try XCTUnwrap(Geohash(geohash: "c23ng"))
    }

    func testExample() throws {
        var cache = GeohashCache<[String]>()

        XCTAssertTrue(cache.activeGeohashes.isEmpty)

        // Add elements for Seattle, and add to the active Geohashes set.
        XCTContext.runActivity(named: "Test insertion into activeGeohashes") { _ in
            cache[seattle] = expectedSeattleElements
            cache.activeGeohashes.insert(seattle)
            XCTAssertEqual(cache[seattle], expectedSeattleElements)
        }

        // Add elements for Bellevue, but don't add it to the active Geohashes set.
        XCTContext.runActivity(named: "Test insertion, but don't add into activeGeohashes") { _ in
            XCTAssertNil(cache[bellevue])
            cache[bellevue] = expectedBellevueElements
            XCTAssertEqual(cache[bellevue], expectedBellevueElements)
        }

        // Test discarding content. After discarding, it is expected that Seattle still exists, but Bellevue is removed.
        XCTContext.runActivity(named: "Test discarding elements of non-activeGeohashes") { _ in
            cache.discardContentIfPossible()

            XCTAssertEqual(cache[seattle], expectedSeattleElements, "Expected Seattle elements to not be removed, since it is an active geohash")
            XCTAssertNil(cache[bellevue], "Expected Bellevue elements to be removed, since it is an inactive geohash")
        }
    }
}
