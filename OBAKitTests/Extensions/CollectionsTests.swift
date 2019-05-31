//
//  CollectionsTests.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 11/23/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import Nimble
import XCTest
@testable import OBAKit

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
