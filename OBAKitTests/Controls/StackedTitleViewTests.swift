//
//  StackedTitleViewTests.swift
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

class StackedTitleViewTests: XCTestCase {
    
    var stackedTitleView: StackedTitleView!
    
    override func setUp() {
        super.setUp()
        stackedTitleView = StackedTitleView(frame: .zero)
    }
    
    func test_init_createsLabels() {
        expect(self.stackedTitleView.titleLabel).to(beAnInstanceOf(UILabel.self))
        expect(self.stackedTitleView.subtitleLabel).to(beAnInstanceOf(UILabel.self))
    }
    
    func test_titleLabel_properties() {
        let titleLabel = stackedTitleView.titleLabel
        
        expect(titleLabel.textAlignment) == .center
        expect(titleLabel.font) == UIFont.preferredFont(forTextStyle: .footnote).bold
        expect(titleLabel.allowsDefaultTighteningForTruncation) == true
        expect(titleLabel.contentCompressionResistancePriority(for: .vertical)) == .required
        expect(titleLabel.contentHuggingPriority(for: .horizontal)) == .defaultLow
    }
    
    func test_subtitleLabel_properties() {
        let subtitleLabel = stackedTitleView.subtitleLabel
        
        expect(subtitleLabel.textAlignment) == .center
        expect(subtitleLabel.font) == UIFont.preferredFont(forTextStyle: .footnote)
        expect(subtitleLabel.allowsDefaultTighteningForTruncation) == true
        expect(subtitleLabel.contentCompressionResistancePriority(for: .vertical)) == .required
        expect(subtitleLabel.contentHuggingPriority(for: .horizontal)) == .defaultLow
    }
    
    func test_stackView_configuration() {
        // Access the stack view indirectly by checking the subviews
        expect(self.stackedTitleView.subviews.count) == 1
        let stackView = self.stackedTitleView.subviews.first as? UIStackView
        expect(stackView).toNot(beNil())
        expect(stackView?.arrangedSubviews.count) == 2
        expect(stackView?.arrangedSubviews.first) === self.stackedTitleView.titleLabel
        expect(stackView?.arrangedSubviews.last) === self.stackedTitleView.subtitleLabel
    }
    
    func test_titleAndSubtitle_canBeSet() {
        stackedTitleView.titleLabel.text = "Test Title"
        stackedTitleView.subtitleLabel.text = "Test Subtitle"
        
        expect(self.stackedTitleView.titleLabel.text) == "Test Title"
        expect(self.stackedTitleView.subtitleLabel.text) == "Test Subtitle"
    }
}
