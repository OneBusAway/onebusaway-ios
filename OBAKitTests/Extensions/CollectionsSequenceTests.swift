//
//  CollectionsSequenceTests.swift
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

/// Tests for `Sequence.sorted(by:)`, `Sequence.filter(type:)`, and `Array.binarySearch(sortedBy:element:)`.
///
/// Covers empty collections, boundary searching, absent keys,
/// and filtering across heterogeneous types.
@Suite(.serialized)
struct CollectionsSequenceTests {

    private struct Item: Equatable {
        let id: Int
        let name: String
        let score: Double
    }

    // MARK: - Sequence sorted(by: KeyPath)

    @Test func `sorted by keyPath orders ascending correctly`() {
        let items = [
            Item(id: 3, name: "Charlie", score: 85.0),
            Item(id: 1, name: "Alice", score: 95.0),
            Item(id: 2, name: "Bob", score: 90.0)
        ]

        let sortedByID = items.sorted(by: \.id)
        #expect(sortedByID.map(\.id) == [1, 2, 3])

        let sortedByName = items.sorted(by: \.name)
        #expect(sortedByName.map(\.name) == ["Alice", "Bob", "Charlie"])

        let sortedByScore = items.sorted(by: \.score)
        #expect(sortedByScore.map(\.score) == [85.0, 90.0, 95.0])
    }

    @Test func `sorted by keyPath on empty sequence returns empty array`() {
        let empty: [Item] = []
        #expect(empty.sorted(by: \.id).isEmpty)
    }

    @Test func `sorted by keyPath preserves single element`() {
        let single = [Item(id: 42, name: "Solo", score: 100.0)]
        #expect(single.sorted(by: \.id) == single)
    }

    // MARK: - Sequence filter(type:)

    @Test func `filter by type separates polymorphic heterogeneous items`() {
        let heterogeneous: [Any] = [
            "string1",
            100,
            "string2",
            200.5,
            300,
            URL(string: "https://example.com")!
        ]

        let strings: [String] = heterogeneous.filter(type: String.self)
        #expect(strings == ["string1", "string2"])

        let ints: [Int] = heterogeneous.filter(type: Int.self)
        #expect(ints == [100, 300])

        let doubles: [Double] = heterogeneous.filter(type: Double.self)
        #expect(doubles == [200.5])

        let dates: [Date] = heterogeneous.filter(type: Date.self)
        #expect(dates.isEmpty)
    }

    // MARK: - Array binarySearch

    @Test func `binarySearch finds first, last, and middle elements`() {
        let list = [
            Item(id: 10, name: "Ten", score: 1.0),
            Item(id: 20, name: "Twenty", score: 2.0),
            Item(id: 30, name: "Thirty", score: 3.0),
            Item(id: 40, name: "Forty", score: 4.0),
            Item(id: 50, name: "Fifty", score: 5.0)
        ]

        // First
        let first = list.binarySearch(sortedBy: \.id, element: 10)
        #expect(first?.index == 0)
        #expect(first?.element.name == "Ten")

        // Middle
        let middle = list.binarySearch(sortedBy: \.id, element: 30)
        #expect(middle?.index == 2)
        #expect(middle?.element.name == "Thirty")

        // Last
        let last = list.binarySearch(sortedBy: \.id, element: 50)
        #expect(last?.index == 4)
        #expect(last?.element.name == "Fifty")
    }

    @Test func `binarySearch returns nil when element is not found`() {
        let list = [
            Item(id: 10, name: "Ten", score: 1.0),
            Item(id: 20, name: "Twenty", score: 2.0),
            Item(id: 30, name: "Thirty", score: 3.0)
        ]

        #expect(list.binarySearch(sortedBy: \.id, element: 5) == nil)
        #expect(list.binarySearch(sortedBy: \.id, element: 15) == nil)
        #expect(list.binarySearch(sortedBy: \.id, element: 99) == nil)
    }

    @Test func `binarySearch on empty array returns nil`() {
        let empty: [Item] = []
        #expect(empty.binarySearch(sortedBy: \.id, element: 10) == nil)
    }
}
