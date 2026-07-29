//
//  VisualEffectViewControllerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import XCTest
import Testing
import UIKit
@testable import OBAKit

@MainActor
class VisualEffectViewControllerTests: XCTestCase {
    
    var viewController: VisualEffectViewController!
    
    override func setUp() async throws {
        try await super.setUp()
        viewController = VisualEffectViewController()
    }
    
    func test_init_setsUpView() {
        #expect(self.viewController != nil)
        #expect(self.viewController.view != nil)
    }
    
    func test_viewDidLoad_setsUpVisualEffectView() {
        viewController.viewDidLoad()
        
        #expect(self.viewController.view.subviews.contains(self.viewController.visualEffectView))
        #expect(self.viewController.view.backgroundColor == UIColor.clear)
    }
    
    func test_visualEffectView_isAccessible() {
        let visualEffectView = viewController.visualEffectView
        #expect(type(of: visualEffectView) == UIVisualEffectView.self)
    }
    
    func test_contentView_throughVisualEffectView() {
        // Test that visualEffectView has a content view  
        let visualEffectView = viewController.visualEffectView
        #expect(type(of: visualEffectView) == UIVisualEffectView.self)
    }
    
    func test_addingSubviewsToContentView() {
        // Trigger viewDidLoad to ensure view is set up
        _ = viewController.view
        
        let testLabel = UILabel()
        testLabel.text = "Test Label"
        
        viewController.visualEffectView.contentView.addSubview(testLabel)
        
        #expect(self.viewController.visualEffectView.contentView.subviews.count == 1)
        #expect(self.viewController.visualEffectView.contentView.subviews.first === testLabel)
    }
}
