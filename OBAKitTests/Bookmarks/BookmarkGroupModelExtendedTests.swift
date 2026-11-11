//
//  BookmarkGroupModelExtendedTests.swift
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

/// Tests for `BookmarkGroup` equality, hashing invariants, UUID uniqueness,
/// sort order mutations, and JSON round-trip coding.
@Suite(.serialized)
final class BookmarkGroupModelExtendedTests: OBATestCase {

    // MARK: - Initializer Invariants

    @Test func `Convenience initializer generates unique UUIDs across instances`() {
        let g1 = BookmarkGroup(name: "Commute", sortOrder: 0)
        let g2 = BookmarkGroup(name: "Commute", sortOrder: 0)

        #expect(g1.name == g2.name)
        #expect(g1.sortOrder == g2.sortOrder)
        #expect(g1.id != g2.id)
        #expect(g1 != g2)
    }

    @Test func `Designated initializer preserves explicit UUID`() {
        let fixedID = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
        let group = BookmarkGroup(name: "Weekend", id: fixedID, sortOrder: 5)

        #expect(group.id == fixedID)
        #expect(group.name == "Weekend")
        #expect(group.sortOrder == 5)
    }

    // MARK: - Equality and Hashing

    @Test func `BookmarkGroup isEqual matches on all three fields`() {
        let id = UUID()
        let g1 = BookmarkGroup(name: "Home", id: id, sortOrder: 1)
        let gIdentical = BookmarkGroup(name: "Home", id: id, sortOrder: 1)
        let gDiffName = BookmarkGroup(name: "Work", id: id, sortOrder: 1)
        let gDiffOrder = BookmarkGroup(name: "Home", id: id, sortOrder: 2)
        let gDiffID = BookmarkGroup(name: "Home", id: UUID(), sortOrder: 1)

        #expect(g1.isEqual(gIdentical))
        #expect(g1 == gIdentical)
        #expect(g1.hash == gIdentical.hash)

        #expect(!g1.isEqual(gDiffName))
        #expect(!g1.isEqual(gDiffOrder))
        #expect(!g1.isEqual(gDiffID))
        #expect(!g1.isEqual("not a group"))
        #expect(!g1.isEqual(nil))
    }

    // MARK: - Codable Round-Tripping

    @Test func `BookmarkGroup encodes and decodes losslessly via JSONEncoder`() throws {
        let id = UUID()
        let original = BookmarkGroup(name: "Downtown Routes", id: id, sortOrder: 42)

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(BookmarkGroup.self, from: data)

        #expect(decoded.name == original.name)
        #expect(decoded.id == original.id)
        #expect(decoded.sortOrder == original.sortOrder)
        #expect(decoded == original)
    }

    // MARK: - Debug Description

    @Test func `BookmarkGroup debugDescription includes name id and sortOrder`() {
        let id = UUID()
        let group = BookmarkGroup(name: "Evening", id: id, sortOrder: 3)
        let desc = group.debugDescription

        #expect(desc.contains("Evening"))
        #expect(desc.contains("3"))
        #expect(desc.contains(id.uuidString))
    }
}
