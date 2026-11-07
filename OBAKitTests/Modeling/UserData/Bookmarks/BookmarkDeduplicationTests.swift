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

    @Test func `dedupedByStopID preserves unique stops and resolves collisions with last-wins precedence`() {
        let bookmark1 = Bookmark(name: "First Bookmark", regionIdentifier: 1, stopID: "1_100")
        let bookmark2 = Bookmark(name: "Second Bookmark", regionIdentifier: 1, stopID: "1_200")
        let bookmark3 = Bookmark(name: "Updated First Bookmark", regionIdentifier: 1, stopID: "1_100")

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
