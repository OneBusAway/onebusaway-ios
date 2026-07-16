//
//  DispatchExtensionsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import XCTest
import Nimble
@testable import OBAKit

@MainActor
class DispatchExtensionsTests: XCTestCase {
    
    func test_debounce_executesAction() {
        let expectation = self.expectation(description: "Debounce executes action")
        
        DispatchQueue.main.debounce(interval: 0.1) {
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0)
    }
    
    func test_throttle_executesAction() {
        let expectation = self.expectation(description: "Throttle executes action")

        DispatchQueue.main.throttle(deadline: .now() + 0.1) {
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    func test_debounce_suppressesSecondCallWithinInterval() {
        let expectation = self.expectation(description: "Debounced action runs exactly once")
        var count = 0

        // Unique context: the debounce bookkeeping is global and would otherwise
        // leak across tests.
        let context = "test_debounce_suppression"
        DispatchQueue.main.debounce(interval: 0.5, context: context) { count += 1 }
        DispatchQueue.main.debounce(interval: 0.5, context: context) { count += 1 }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertEqual(count, 1)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }
}
