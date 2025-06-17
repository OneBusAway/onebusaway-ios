//
//  VisualEffectContainerViewTests.swift
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

class VisualEffectContainerViewTests: XCTestCase {
    
    var containerView: VisualEffectContainerView!
    
    override func setUp() {
        super.setUp()
        let blurEffect = UIBlurEffect(style: .regular)
        containerView = VisualEffectContainerView(blurEffect: blurEffect)
    }
    
    func test_init_createsEffectView() {
        expect(self.containerView).toNot(beNil())
        expect(self.containerView.subviews.count) == 1
        expect(self.containerView.subviews.first).to(beAnInstanceOf(UIVisualEffectView.self))
    }
    
    func test_contentView_isEffectViewContentView() {
        let contentView = containerView.contentView
        expect(contentView).toNot(beNil())
        
        // Verify it's the content view from the visual effect view
        let effectView = containerView.subviews.first as? UIVisualEffectView
        expect(contentView) === effectView?.contentView
    }
    
    func test_addingSubviewsToContentView() {
        let testLabel = UILabel()
        testLabel.text = "Test Label"
        
        containerView.contentView.addSubview(testLabel)
        
        expect(self.containerView.contentView.subviews.count) == 1
        expect(self.containerView.contentView.subviews.first) === testLabel
    }
    
    func test_visualEffectViewConstraints() {
        // Verify the effect view is properly constrained
        let effectView = containerView.subviews.first as? UIVisualEffectView
        expect(effectView?.translatesAutoresizingMaskIntoConstraints) == false
        
        // Test that constraints exist (we can't easily test exact constraints in unit tests)
        expect(self.containerView.constraints.count).to(beGreaterThan(0))
    }
    
    func test_initWithCoder_fatalError() {
        // Test that init(coder:) is not implemented
        expect {
            _ = VisualEffectContainerView(coder: NSCoder())
        }.to(throwAssertion())
    }
}
