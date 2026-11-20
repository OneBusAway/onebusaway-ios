//
//  CollectionsTests.swift
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

@MainActor
@Suite(.serialized)
final class CollectionsTests {

    @Test func `Set all objects`() {
        let mySet: Set = ["one", "two", "three"]
        let array = mySet.allObjects

        #expect(array.contains("one"))
        #expect(array.contains("two"))
        #expect(array.contains("three"))
    }

    @Test func filter() {
        let list: [Any] = [1, "two", 3, "four", 5]
        let filtered = list.filter(type: Int.self)
        #expect(filtered == [1, 3, 5])
    }

    // MARK: - Array.uniqued

    @Test func `Array uniqued removes duplicates while strictly preserving insertion order`() {
        let duplicates = ["apple", "banana", "apple", "orange", "banana", "grape", "apple"]
        let uniqueList = duplicates.uniqued

        #expect(uniqueList == ["apple", "banana", "orange", "grape"])
    }

    @Test func `Array uniqued on already unique elements preserves exact list`() {
        let uniqueInput = [10, 20, 30, 40]
        #expect(uniqueInput.uniqued == uniqueInput)
    }

    @Test func `Array uniqued on empty array returns empty array`() {
        let empty: [String] = []
        #expect(empty.uniqued.isEmpty)
    }

    @Test func `Array uniqued on repeated single element returns single element array`() {
        let repeated = [42, 42, 42, 42, 42]
        #expect(repeated.uniqued == [42])
    }
}
