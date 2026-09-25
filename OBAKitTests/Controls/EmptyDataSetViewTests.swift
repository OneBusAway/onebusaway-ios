//
//  EmptyDataSetViewTests.swift
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
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class EmptyDataSetViewTests {
    
    @Test func testInitializationDefaults() {
        let emptyView = EmptyDataSetView()
        
        #expect(emptyView.alignment == .center)
        #expect(emptyView.topConstraint.priority == .defaultLow)
        #expect(emptyView.centerYConstraint.priority == .required)
        #expect(emptyView.bottomConstraint.priority == .defaultLow)
    }
    
    @Test func testTopAlignmentConstraintPriorities() {
        let emptyView = EmptyDataSetView(alignment: .top)
        
        #expect(emptyView.topConstraint.priority == .required)
        #expect(emptyView.centerYConstraint.priority == .defaultLow)
        #expect(emptyView.bottomConstraint.priority == .required)
        
        let hostView = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        hostView.addSubview(emptyView)
        emptyView.frame = hostView.bounds
        emptyView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        emptyView.titleLabel.text = "Test"
        hostView.layoutIfNeeded()
        
        let labelY = emptyView.titleLabel.convert(CGPoint.zero, to: emptyView).y
        #expect(labelY < 240, "Top alignment should place content above the center")
    }

    @Test func testAlignmentUpdatesConstraints() {
        let emptyView = EmptyDataSetView(alignment: .center)
        let hostView = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        hostView.addSubview(emptyView)
        emptyView.frame = hostView.bounds
        emptyView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        emptyView.titleLabel.text = "Test"
        hostView.layoutIfNeeded()
        
        let centerLabelY = emptyView.titleLabel.convert(CGPoint.zero, to: emptyView).y
        
        emptyView.alignment = .top
        hostView.setNeedsLayout()
        hostView.layoutIfNeeded()
        
        let topLabelY = emptyView.titleLabel.convert(CGPoint.zero, to: emptyView).y
        
        #expect(emptyView.topConstraint.priority == .required)
        #expect(emptyView.centerYConstraint.priority == .defaultLow)
        #expect(emptyView.bottomConstraint.priority == .required)
        
        #expect(topLabelY < centerLabelY, "Top alignment should position the content higher than center alignment.")
    }

    @Test func testTextColorPropertySyncsLabels() {
        let emptyView = EmptyDataSetView()
        let color = UIColor.red
        emptyView.textColor = color
        
        #expect(emptyView.titleLabel.textColor == color)
        #expect(emptyView.bodyLabel.textColor == color)
        #expect(emptyView.imageView.tintColor == color)
    }

    @Test func testImageTintColorOverridesTextColor() {
        let emptyView = EmptyDataSetView()
        emptyView.textColor = UIColor.red
        emptyView.imageTintColor = UIColor.blue
        
        #expect(emptyView.titleLabel.textColor == UIColor.red)
        #expect(emptyView.bodyLabel.textColor == UIColor.red)
        #expect(emptyView.imageView.tintColor == UIColor.blue)
    }

    @Test func testConfigureWithError() {
        let emptyView = EmptyDataSetView()
        
        let error = NSError(domain: "TestDomain", code: 42, userInfo: [NSLocalizedDescriptionKey: "Something went wrong."])
        emptyView.configure(with: error)
        
        #expect(emptyView.bodyLabel.text == "Something went wrong.")
    }
}
