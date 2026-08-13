//
//  ModalDelegateTests.swift
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
final class ModalDelegateTests {
    
    @Test func `Modal delegate protocol`() {
        // Test that a class can conform to ModalDelegate
        class TestModalDelegate: NSObject, ModalDelegate {
            var dismissedController: UIViewController?
            
            func dismissModalController(_ controller: UIViewController) {
                dismissedController = controller
            }
        }
        
        let delegate = TestModalDelegate()
        let controller = UIViewController()
        
        delegate.dismissModalController(controller)
        
        #expect(delegate.dismissedController === controller)
    }
}
