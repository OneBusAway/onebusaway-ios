//
//  ProgressHUDExtensionsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import UIKit
@testable import OBAKit

@MainActor
@Suite(.serialized)
final class ProgressHUDExtensionsTests {
    
    @Test func `Show success and dismiss with message`() {
        // This test is limited since ProgressHUD is a third-party library
        // and we can't easily mock its behavior in unit tests
        // But we can verify the method exists and doesn't crash when called
        
        ProgressHUD.showSuccessAndDismiss(message: "Test Message", dismissAfter: 0.1)
        
        // Verify the method completes without throwing
        #expect(true)
    }
    
    @Test func `Show success and dismiss without message`() {
        ProgressHUD.showSuccessAndDismiss(dismissAfter: 0.1)
        
        // Verify the method completes without throwing
        #expect(true)
    }
}
