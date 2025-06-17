//
//  PreviewableTests.swift
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

class PreviewableTests: XCTestCase {
    
    func test_Previewable_protocol() {
        // Test that a class can conform to Previewable
        class TestPreviewableController: UIViewController, Previewable {
            var enteredPreviewMode = false
            var exitedPreviewMode = false
            
            func enterPreviewMode() {
                enteredPreviewMode = true
            }
            
            func exitPreviewMode() {
                exitedPreviewMode = true
            }
        }
        
        let controller = TestPreviewableController()
        
        controller.enterPreviewMode()
        expect(controller.enteredPreviewMode) == true
        
        controller.exitPreviewMode()
        expect(controller.exitedPreviewMode) == true
    }
    
    func test_ControllerPreviewProvider_typealias() {
        // Test that the typealias works correctly
        let provider: ControllerPreviewProvider = {
            return UIViewController()
        }
        
        let controller = provider()
        expect(controller).to(beAnInstanceOf(UIViewController.self))
    }
}
