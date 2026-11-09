//
//  OnDemandLocationGroupExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

/// Tests for `OnDemandLocationGroup` JSON decoding, blank name handling,
/// stop ID collection defaults, and hash consistency.
@Suite(.serialized)
struct OnDemandLocationGroupExtendedTests {

    // MARK: - Decoding

    @Test func `OnDemandLocationGroup decodes ID, name, and stopIDs array`() throws {
        let json = """
        {
            "id": "group_transfer_center",
            "name": "Transit Center Hub",
            "stopIds": ["1_1001", "1_1002", "1_1003"]
        }
        """.data(using: .utf8)!

        let group = try JSONDecoder().decode(OnDemandLocationGroup.self, from: json)

        #expect(group.id == "group_transfer_center")
        #expect(group.name == "Transit Center Hub")
        #expect(group.stopIDs == ["1_1001", "1_1002", "1_1003"])
    }

    @Test func `OnDemandLocationGroup defaults missing stopIds to empty array`() throws {
        let json = """
        {
            "id": "empty_group",
            "name": "Zone Anchor"
        }
        """.data(using: .utf8)!

        let group = try JSONDecoder().decode(OnDemandLocationGroup.self, from: json)

        #expect(group.id == "empty_group")
        #expect(group.name == "Zone Anchor")
        #expect(group.stopIDs.isEmpty)
    }

    @Test func `OnDemandLocationGroup nilifies blank or whitespace-only name`() throws {
        let json = """
        {
            "id": "unnamed_group",
            "name": "   ",
            "stopIds": ["1_500"]
        }
        """.data(using: .utf8)!

        let group = try JSONDecoder().decode(OnDemandLocationGroup.self, from: json)

        #expect(group.id == "unnamed_group")
        #expect(group.name == nil)
        #expect(group.stopIDs == ["1_500"])
    }

    // MARK: - Hashable & Equatable

    @Test func `OnDemandLocationGroup operates in Hashable collections`() throws {
        let json1 = "{\"id\": \"g1\", \"name\": \"Hub\", \"stopIds\": [\"s1\"]}".data(using: .utf8)!
        let json2 = "{\"id\": \"g1\", \"name\": \"Hub\", \"stopIds\": [\"s1\"]}".data(using: .utf8)!
        let json3 = "{\"id\": \"g2\", \"name\": \"Hub\", \"stopIds\": [\"s1\"]}".data(using: .utf8)!

        let g1 = try JSONDecoder().decode(OnDemandLocationGroup.self, from: json1)
        let g2 = try JSONDecoder().decode(OnDemandLocationGroup.self, from: json2)
        let g3 = try JSONDecoder().decode(OnDemandLocationGroup.self, from: json3)

        #expect(g1 == g2)
        #expect(g1.hashValue == g2.hashValue)
        #expect(g1 != g3)

        let set: Set<OnDemandLocationGroup> = [g1, g2, g3]
        #expect(set.count == 2)
    }
}
