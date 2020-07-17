//
//  CollectionsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Nimble
import XCTest
@testable import OBAKit
@testable import OBAKitCore

class CollectionsTests: XCTestCase {

    func test_set_allObjects() {
        let mySet: Set = ["one", "two", "three"]
        let array = mySet.allObjects

        expect(array).to(contain("one"))
        expect(array).to(contain("two"))
        expect(array).to(contain("three"))
    }

    func testFilter() {
        let list: [Any] = [1, "two", 3, "four", 5]
        let filtered = list.filter(type: Int.self)
        expect(filtered) == [1, 3, 5]
    }
}
