//
//  StackedButtonTests.swift
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
@testable import OBAKitCore

class StackedButtonTests: XCTestCase {
    
    var stackedButton: StackedButton!
    
    override func setUp() {
        super.setUp()
        stackedButton = StackedButton(frame: .zero)
    }
    
    func test_init_setsDefaultProperties() {
        expect(self.stackedButton.translatesAutoresizingMaskIntoConstraints) == false
        expect(self.stackedButton.isUserInteractionEnabled) == true
        expect(self.stackedButton.backgroundColor) == .clear
    }
    
    func test_title_getterAndSetter() {
        let testTitle = "Test Button"
        stackedButton.title = testTitle
        
        expect(self.stackedButton.title) == testTitle
        expect(self.stackedButton.textLabel.text) == testTitle
        expect(self.stackedButton.accessibilityLabel) == testTitle
    }
    
    func test_title_nilValue() {
        stackedButton.title = nil
        
        expect(self.stackedButton.title).to(beNil())
        expect(self.stackedButton.textLabel.text).to(beNil())
        expect(self.stackedButton.accessibilityLabel).to(beNil())
    }
    
    func test_textLabel_properties() {
        let textLabel = stackedButton.textLabel
        
        expect(textLabel.numberOfLines) == 1
        expect(textLabel.textColor) == ThemeColors.shared.brand
        expect(textLabel.textAlignment) == .center
        expect(textLabel.isUserInteractionEnabled) == false
        expect(textLabel.contentCompressionResistancePriority(for: .vertical)) == .required
        expect(textLabel.contentCompressionResistancePriority(for: .horizontal)) == .required
        expect(textLabel.contentHuggingPriority(for: .horizontal)) == .required
        expect(textLabel.font) == UIFont.preferredFont(forTextStyle: .footnote).bold
    }
    
    func test_imageView_properties() {
        let imageView = stackedButton.imageView
        
        expect(imageView.contentMode) == .scaleAspectFit
        expect(imageView.contentHuggingPriority(for: .vertical)) == .required
        expect(imageView.contentHuggingPriority(for: .horizontal)) == .required
        expect(imageView.contentCompressionResistancePriority(for: .horizontal)) == .required
        expect(imageView.isUserInteractionEnabled) == false
        expect(imageView.tintColor) == ThemeColors.shared.brand
    }
    
    func test_imageView_canSetImage() {
        let testImage = UIImage(systemName: "star")
        stackedButton.imageView.image = testImage
        
        expect(self.stackedButton.imageView.image) == testImage
    }
    
    func test_stackView_configuration() {
        // Check that the button has the expected subview structure
        expect(self.stackedButton.subviews.count) == 1
        
        // The wrapper view should contain the stack view
        let wrapperView = self.stackedButton.subviews.first!
        expect(wrapperView.subviews.count) == 1
        
        let stackView = wrapperView.subviews.first as? UIStackView
        expect(stackView).toNot(beNil())
        expect(stackView?.arrangedSubviews.count) == 2
        expect(stackView?.arrangedSubviews.first) === self.stackedButton.imageView
        expect(stackView?.arrangedSubviews.last) === self.stackedButton.textLabel
        expect(stackView?.isUserInteractionEnabled) == false
    }
}
