//
//  BookmarkDeduplicationTests.swift
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
final class BookmarkDeduplicationTests: OBATestCase {

    private func makeTestStop(id: String) throws -> Stop {
        let dict: [String: Any] = [
            "id": id,
            "name": "Test Stop \(id)",
            "lat": 47.6062,
            "lon": -122.3321,
            "routeIds": ["1_100"]
        ]
        return try Fixtures.dictionaryToModel(type: Stop.self, dictionary: dict)
    }

    @Test func `dedupedByStopID preserves unique stops and resolves collisions with last-wins precedence`() throws {
        let stop1 = try makeTestStop(id: "1_100")
        let stop2 = try makeTestStop(id: "1_200")

        let bookmark1 = Bookmark(name: "First Bookmark", regionIdentifier: 1, stop: stop1)
        let bookmark2 = Bookmark(name: "Second Bookmark", regionIdentifier: 1, stop: stop2)
        let bookmark3 = Bookmark(name: "Updated First Bookmark", regionIdentifier: 1, stop: stop1)

        let bookmarks = [bookmark1, bookmark2, bookmark3]
        let deduped = bookmarks.dedupedByStopID()

        #expect(deduped.count == 2)
        #expect(deduped["1_200"]?.name == "Second Bookmark")
        #expect(deduped["1_100"]?.name == "Updated First Bookmark", "Collision must follow last-wins precedence")
    }

    @Test func `dedupedByStopID on empty collection returns empty dictionary`() {
        let emptyBookmarks = [Bookmark]()
        let deduped = emptyBookmarks.dedupedByStopID()
        #expect(deduped.isEmpty)
    }
}
