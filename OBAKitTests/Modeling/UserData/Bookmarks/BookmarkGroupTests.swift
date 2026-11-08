//
//  BookmarkGroupTests.swift
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
final class BookmarkGroupTests: OBATestCase {

    @Test func creation() {
        let group = BookmarkGroup(name: "Group 1", sortOrder: 0)
        #expect(group.name == "Group 1")
    }

    @Test func `Codable roundtripping`() {
        let group = BookmarkGroup(name: "Group 1", sortOrder: 10)
        let decoded = try! Fixtures.roundtripCodable(type: BookmarkGroup.self, model: group)

        #expect(decoded.name == "Group 1")
        #expect(decoded.id == group.id)
        #expect(decoded.sortOrder == 10)
    }

    // MARK: - Equality, Hashing and Inequality

    @Test func `BookmarkGroup equality with identical attributes`() {
        let uuid = UUID()
        let group1 = BookmarkGroup(name: "Work", id: uuid, sortOrder: 5)
        let group2 = BookmarkGroup(name: "Work", id: uuid, sortOrder: 5)

        #expect(group1.isEqual(group2))
        #expect(group1.hash == group2.hash)
    }

    @Test func `BookmarkGroup inequality when attributes differ`() {
        let uuid1 = UUID()
        let uuid2 = UUID()
        let group1 = BookmarkGroup(name: "Work", id: uuid1, sortOrder: 5)
        let groupDiffID = BookmarkGroup(name: "Work", id: uuid2, sortOrder: 5)
        let groupDiffName = BookmarkGroup(name: "Home", id: uuid1, sortOrder: 5)
        let groupDiffOrder = BookmarkGroup(name: "Work", id: uuid1, sortOrder: 10)

        #expect(!group1.isEqual(groupDiffID))
        #expect(!group1.isEqual(groupDiffName))
        #expect(!group1.isEqual(groupDiffOrder))
        #expect(!group1.isEqual("non_group_object"))
        #expect(!group1.isEqual(nil))
    }

    @Test func `BookmarkGroup debugDescription contains identifying fields`() {
        let uuid = UUID()
        let group = BookmarkGroup(name: "Transit", id: uuid, sortOrder: 3)
        let desc = group.debugDescription

        #expect(desc.contains("Transit"))
        #expect(desc.contains("3"))
        #expect(desc.contains(uuid.uuidString))
    }
}
