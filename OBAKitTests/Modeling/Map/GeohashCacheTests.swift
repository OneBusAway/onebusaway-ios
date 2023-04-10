//
//  GeohashCacheTests.swift
//  OBAKitTests
//
//  Created by Alan Chu on 4/10/23.
//

import XCTest
import GeohashKit
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
    }

    func testDifference() throws {
        // MARK: Setup
        var cache = GeohashCache<[String]>()

        cache[seattle] = expectedSeattleElements
        cache[bellevue] = expectedBellevueElements

        cache.activeGeohashes = [seattle]

        // MARK: Test
        // After discarding, it is expected that Seattle still exists, but Bellevue is removed.
        let difference = cache.discardContentIfPossible()

        XCTContext.runActivity(named: "Test element difference") { _ in
            var removedElements: [[String]] = []
            for diff in difference.elementChanges {
                switch diff {
                case .insertion(_):
                    XCTFail("There should be no insertion changes")
                case .removal(let element):
                    removedElements.append(element)
                }
            }

            XCTAssertEqual(removedElements.count, 1)
            XCTAssertEqual(removedElements.first, expectedBellevueElements)
        }

        XCTContext.runActivity(named: "Test key difference") { _ in
            var removedKeys: Set<Geohash> = []
            for diff in difference.keyChanges {
                switch diff {
                case .insertion(_):
                    XCTFail("There should be no insertion changes")
                case .removal(let key):
                    removedKeys.insert(key)
                }
            }

            XCTAssertEqual(removedKeys.count, 1)
            XCTAssertEqual(removedKeys.first, bellevue)
        }
    }

    func testUpsert() throws {
        var cache = GeohashCache<[String]>()

        // Testing initial insertion.
        // - Expected key changes: one insertion.
        // - Expected element changes: one insertion.
        let initialSeattleElement = ["initial", "element"]
        let initialDifference = cache.upsert(geohash: seattle, element: initialSeattleElement)

        XCTAssertEqual(initialDifference.keyChanges.count, 1)
        XCTAssertEqual(initialDifference.keyChanges.first, .insertion(seattle))

        XCTAssertEqual(initialDifference.elementChanges.count, 1)
        XCTAssertEqual(initialDifference.elementChanges.first, .insertion(initialSeattleElement))

        // Testing updating of existing geohash.
        // - Expected key changes: zero.
        // - Expected element changes: one removal and one insertion.
        let secondSeattleElement = ["final", "seattle"]
        let secondDifference = cache.upsert(geohash: seattle, element: secondSeattleElement)

        XCTAssertTrue(secondDifference.keyChanges.isEmpty)

        XCTAssertEqual(secondDifference.elementChanges.count, 2)
        XCTAssertEqual(secondDifference.elementChanges[0], .removal(initialSeattleElement), "Removal should occur first in the diff collection")
        XCTAssertEqual(secondDifference.elementChanges[1], .insertion(secondSeattleElement), "Insertion should occur after the removal")

        // Test upserting a new geohash, with at least 1 other existing geohash
        let initialBellevueElement = ["bellevue"]

        let initialBellevueDifference = cache.upsert(geohash: bellevue, element: initialBellevueElement)
        XCTAssertEqual(initialBellevueDifference.keyChanges.count, 1)
        XCTAssertEqual(initialBellevueDifference.keyChanges.first, .insertion(bellevue))

        XCTAssertEqual(initialBellevueDifference.elementChanges.count, 1)
        XCTAssertEqual(initialBellevueDifference.elementChanges.first, .insertion(initialBellevueElement))
    }
}
