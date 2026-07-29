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
}
