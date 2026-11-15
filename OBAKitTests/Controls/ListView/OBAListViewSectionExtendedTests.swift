//
//  OBAListViewSectionExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class OBAListViewSectionExtendedTests: OBATestCase {

    private struct MockItem: OBAListViewItem {
        let id: String
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
        static func == (lhs: MockItem, rhs: MockItem) -> Bool {
            lhs.id == rhs.id
        }
    }

    @Test func `Section initialization with title exposes hasHeader true`() {
        let item = MockItem(id: "item_1")
        let section = OBAListViewSection(id: "sec_1", title: "Header Title", contents: [item])

        #expect(section.id == "sec_1")
        #expect(section.title == "Header Title")
        #expect(section.hasHeader == true)
        #expect(section.contents.count == 1)
        #expect(section.collapseState == nil)
    }

    @Test func `Section initialization with empty title still exposes hasHeader true`() {
        let item = MockItem(id: "item_empty")
        let section = OBAListViewSection(id: "sec_empty", title: "", contents: [item])

        #expect(section.hasHeader == true)
        #expect(section.title == "")
    }

    @Test func `Section initialization with nil title exposes hasHeader false`() {
        let item = MockItem(id: "item_nil")
        let section = OBAListViewSection(id: "sec_nil", title: nil, contents: [item])

        #expect(section.hasHeader == false)
        #expect(section.title == nil)
    }

    @Test func `Subscript safely accesses items within bounds and returns nil out of bounds`() {
        let item0 = MockItem(id: "0")
        let item1 = MockItem(id: "1")
        let section = OBAListViewSection(id: "sec_bounds", title: "Bounds", contents: [item0, item1])

        #expect(section[0] != nil)
        #expect(section[1] != nil)
        #expect(section[-1] == nil)
        #expect(section[2] == nil)
        #expect(section[100] == nil)
    }

    @Test func `Equality ignores collapseState differences but respects id, title, and contents`() {
        let itemA = MockItem(id: "A")
        let itemB = MockItem(id: "B")

        var section1 = OBAListViewSection(id: "sec_eq", title: "Title", contents: [itemA])
        section1.collapseState = .collapsed

        var section2 = OBAListViewSection(id: "sec_eq", title: "Title", contents: [itemA])
        section2.collapseState = .expanded

        #expect(section1 == section2)

        let sectionDifferentID = OBAListViewSection(id: "sec_diff", title: "Title", contents: [itemA])
        #expect(section1 != sectionDifferentID)

        let sectionDifferentTitle = OBAListViewSection(id: "sec_eq", title: "Other Title", contents: [itemA])
        #expect(section1 != sectionDifferentTitle)

        let sectionDifferentContents = OBAListViewSection(id: "sec_eq", title: "Title", contents: [itemB])
        #expect(section1 != sectionDifferentContents)
    }

    @Test func `Hashing produces consistent hash values across matching sections`() {
        let item = MockItem(id: "hash_item")
        let sec1 = OBAListViewSection(id: "sec_hash", title: "Hash", contents: [item])
        let sec2 = OBAListViewSection(id: "sec_hash", title: "Hash", contents: [item])

        var hasher1 = Hasher()
        sec1.hash(into: &hasher1)

        var hasher2 = Hasher()
        sec2.hash(into: &hasher2)

        #expect(hasher1.finalize() == hasher2.finalize())
    }
}
