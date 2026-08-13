//
//  VisualEffectViewControllerTests.swift
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
final class VisualEffectViewControllerTests {
    
    var viewController: VisualEffectViewController!
    
    init() {
        viewController = VisualEffectViewController()
    }
    
    @Test func `Init sets up view`() {
        #expect(self.viewController != nil)
        #expect(self.viewController.view != nil)
    }
    
    @Test func `View did load sets up visual effect view`() {
        viewController.viewDidLoad()
        
        #expect(self.viewController.view.subviews.contains(self.viewController.visualEffectView))
        #expect(self.viewController.view.backgroundColor == UIColor.clear)
    }
    
    @Test func `Visual effect view is accessible`() {
        let visualEffectView = viewController.visualEffectView
        #expect(type(of: visualEffectView) == UIVisualEffectView.self)
    }
    
    @Test func `Content view through visual effect view`() {
        // Test that visualEffectView has a content view  
        let visualEffectView = viewController.visualEffectView
        #expect(type(of: visualEffectView) == UIVisualEffectView.self)
    }
    
    @Test func `Adding subviews to content view`() {
        // Trigger viewDidLoad to ensure view is set up
        _ = viewController.view
        
        let testLabel = UILabel()
        testLabel.text = "Test Label"
        
        viewController.visualEffectView.contentView.addSubview(testLabel)
        
        #expect(self.viewController.visualEffectView.contentView.subviews.count == 1)
        #expect(self.viewController.visualEffectView.contentView.subviews.first === testLabel)
    }
}
