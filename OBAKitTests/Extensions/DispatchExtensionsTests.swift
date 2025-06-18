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
}
