//
//  AutoLayoutExtensionsTests.swift
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
@testable import OBAKitCore

class AutoLayoutExtensionsTests: XCTestCase {
    
    func test_UIView_layoutDirectionIsRTL() {
        let view = UIView()
        
        // For most locales, this should be false
        view.semanticContentAttribute = .unspecified
        expect(view.layoutDirectionIsRTL) == false
        
        // Force RTL
        view.semanticContentAttribute = .forceRightToLeft
        expect(view.layoutDirectionIsRTL) == true
    }
    
    func test_UIView_layoutDirectionIsLTR() {
        let view = UIView()
        
        // For most locales, this should be true
        view.semanticContentAttribute = .unspecified
        expect(view.layoutDirectionIsLTR) == true
        
        // Force RTL should make LTR false
        view.semanticContentAttribute = .forceRightToLeft
        expect(view.layoutDirectionIsLTR) == false
        
        // Force LTR
        view.semanticContentAttribute = .forceLeftToRight
        expect(view.layoutDirectionIsLTR) == true
    }
    
    func test_UIView_autolayoutNew() {
        let view = UIView.autolayoutNew()
        
        expect(view.translatesAutoresizingMaskIntoConstraints) == false
        expect(view.frame) == .zero
    }
    
    func test_UILabel_autolayoutNew() {
        let label = UILabel.autolayoutNew()
        
        expect(label.translatesAutoresizingMaskIntoConstraints) == false
        expect(label.frame) == .zero
        expect(label).to(beAnInstanceOf(UILabel.self))
    }
    
    func test_UIView_spacerView() {
        let height: CGFloat = 20.0
        let spacer = UIView.spacerView(height: height)
        
        expect(spacer.translatesAutoresizingMaskIntoConstraints) == false
        
        // Check that the height constraint was applied
        let heightConstraints = spacer.constraints.filter { constraint in
            constraint.firstAttribute == .height && constraint.constant == height
        }
        expect(heightConstraints.count) == 1
    }
    
    func test_UIView_embedInWrapperView_withConstraints() {
        let childView = UIView()
        let wrapper = childView.embedInWrapperView(setConstraints: true)
        
        expect(wrapper.translatesAutoresizingMaskIntoConstraints) == false
        expect(wrapper.subviews.count) == 1
        expect(wrapper.subviews.first) === childView
        expect(childView.superview) === wrapper
    }
    
    func test_UIView_embedInWrapperView_withoutConstraints() {
        let childView = UIView()
        let wrapper = childView.embedInWrapperView(setConstraints: false)
        
        expect(wrapper.translatesAutoresizingMaskIntoConstraints) == false
        expect(wrapper.subviews.count) == 1
        expect(wrapper.subviews.first) === childView
        expect(childView.superview) === wrapper
    }
    
    func test_AutoLayoutPinTarget_cases() {
        expect(UIView.AutoLayoutPinTarget.edges.rawValue) == 0
        expect(UIView.AutoLayoutPinTarget.layoutMargins.rawValue) == 1
        expect(UIView.AutoLayoutPinTarget.readableContent.rawValue) == 2
        expect(UIView.AutoLayoutPinTarget.safeArea.rawValue) == 3
    }
    
    func test_LayoutConstraints_struct() {
        let view = UIView()
        let superview = UIView()
        superview.addSubview(view)
        
        // Create some dummy constraints to test the struct
        let top = view.topAnchor.constraint(equalTo: superview.topAnchor)
        let bottom = view.bottomAnchor.constraint(equalTo: superview.bottomAnchor)
        let leading = view.leadingAnchor.constraint(equalTo: superview.leadingAnchor)
        let trailing = view.trailingAnchor.constraint(equalTo: superview.trailingAnchor)
        
        let layoutConstraints = UIView.LayoutConstraints(
            top: top,
            bottom: bottom,
            leading: leading,
            trailing: trailing
        )
        
        expect(layoutConstraints.top) === top
        expect(layoutConstraints.bottom) === bottom
        expect(layoutConstraints.leading) === leading
        expect(layoutConstraints.trailing) === trailing
    }
}
