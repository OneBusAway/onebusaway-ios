//
//  PaddingLabelTests.swift
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
final class PaddingLabelTests {
    
    @Test func testInitializationWithInsets() {
        let insets = UIEdgeInsets(top: 10, left: 15, bottom: 20, right: 25)
        let label = PaddingLabel(insets: insets)
        
        #expect(label.insets == insets)
        #expect(label.cornerRadius == 0)
    }

    @Test func testDefaultInitialization() {
        let label = PaddingLabel(frame: .zero)
        
        let expectedInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        #expect(label.insets == expectedInsets)
    }

    @Test func testIntrinsicContentSize() {
        let insets = UIEdgeInsets(top: 10, left: 15, bottom: 20, right: 25)
        let label = PaddingLabel(insets: insets)
        label.text = "Test"
        label.font = UIFont.systemFont(ofSize: 12)
        label.sizeToFit()
        
        // intrinsicContentSize should include the insets
        let size = label.intrinsicContentSize
        let superSize = superIntrinsicSize(for: label)
        
        #expect(size.width == superSize.width + insets.left + insets.right)
        #expect(size.height == superSize.height + insets.top + insets.bottom)
    }

    @Test func testCornerRadius() {
        let label = PaddingLabel(frame: .zero)
        
        label.cornerRadius = 8.0
        #expect(label.layer.cornerRadius == 8.0)
        #expect(label.layer.masksToBounds == true)
        
        label.cornerRadius = 0.0
        #expect(label.layer.cornerRadius == 0.0)
        #expect(label.layer.masksToBounds == false)
    }
    
    // Helper to get the super class's intrinsic content size since we can't call super here directly
    private func superIntrinsicSize(for label: UILabel) -> CGSize {
        let plainLabel = UILabel()
        plainLabel.text = label.text
        plainLabel.font = label.font
        return plainLabel.intrinsicContentSize
    }
}
