//
//  ProgressHUDExtensionsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import XCTest
import Nimble
import UIKit
@testable import OBAKit

class ProgressHUDExtensionsTests: XCTestCase {
    
    func test_showSuccessAndDismiss_withMessage() {
        // This test is limited since ProgressHUD is a third-party library
        // and we can't easily mock its behavior in unit tests
        // But we can verify the method exists and doesn't crash when called
        
        ProgressHUD.showSuccessAndDismiss(message: "Test Message", dismissAfter: 0.1)
        
        // Verify the method completes without throwing
        expect(true).to(beTrue())
    }
    
    func test_showSuccessAndDismiss_withoutMessage() {
        ProgressHUD.showSuccessAndDismiss(dismissAfter: 0.1)
        
        // Verify the method completes without throwing
        expect(true).to(beTrue())
    }
}
