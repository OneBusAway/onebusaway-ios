//
//  VisualEffectContainerViewTests.swift
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
final class VisualEffectContainerViewTests {
    
    var containerView: VisualEffectContainerView!
    
    init() {
        let blurEffect = UIBlurEffect(style: .regular)
        containerView = VisualEffectContainerView(blurEffect: blurEffect)
    }
    
    @Test func `Init creates effect view`() {
        #expect(self.containerView != nil)
        #expect(self.containerView.subviews.count == 1)
        #expect(self.containerView.subviews.first.map { type(of: $0) == UIVisualEffectView.self } == true)
    }
    
    @Test func `Content view is effect view content view`() {
        let contentView = containerView.contentView
        
        // Verify it's the content view from the visual effect view
        let effectView = containerView.subviews.first as? UIVisualEffectView
        #expect(contentView === effectView?.contentView)
    }
    
    @Test func `Adding subviews to content view`() {
        let testLabel = UILabel()
        testLabel.text = "Test Label"
        
        containerView.contentView.addSubview(testLabel)
        
        #expect(self.containerView.contentView.subviews.count == 1)
        #expect(self.containerView.contentView.subviews.first === testLabel)
    }
    
    @Test func `Visual effect view constraints`() {
        // Verify the effect view is properly constrained
        let effectView = containerView.subviews.first as? UIVisualEffectView
        #expect(effectView?.translatesAutoresizingMaskIntoConstraints == false)
        
        // Test that constraints exist (we can't easily test exact constraints in unit tests)
        #expect(self.containerView.constraints.count > 0)
    }
}
