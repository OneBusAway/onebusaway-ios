//
//  StackedTitleViewTests.swift
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
final class StackedTitleViewTests {
    
    var stackedTitleView: StackedTitleView!
    
    init() {
        stackedTitleView = StackedTitleView(frame: .zero)
    }
    
    @Test func `Init creates labels`() {
        #expect(type(of: self.stackedTitleView.titleLabel) == UILabel.self)
        #expect(type(of: self.stackedTitleView.subtitleLabel) == UILabel.self)
    }
    
    @Test func `Title label properties`() {
        let titleLabel = stackedTitleView.titleLabel
        
        #expect(titleLabel.textAlignment == .center)
        #expect(titleLabel.font == UIFont.preferredFont(forTextStyle: .footnote).bold)
        #expect(titleLabel.allowsDefaultTighteningForTruncation == true)
        #expect(titleLabel.contentCompressionResistancePriority(for: .vertical) == .required)
        #expect(titleLabel.contentHuggingPriority(for: .horizontal) == .defaultLow)
    }
    
    @Test func `Subtitle label properties`() {
        let subtitleLabel = stackedTitleView.subtitleLabel
        
        #expect(subtitleLabel.textAlignment == .center)
        #expect(subtitleLabel.font == UIFont.preferredFont(forTextStyle: .footnote))
        #expect(subtitleLabel.allowsDefaultTighteningForTruncation == true)
        #expect(subtitleLabel.contentCompressionResistancePriority(for: .vertical) == .required)
        #expect(subtitleLabel.contentHuggingPriority(for: .horizontal) == .defaultLow)
    }
    
    @Test func `Stack view configuration`() {
        // Access the stack view indirectly by checking the subviews
        #expect(self.stackedTitleView.subviews.count == 1)
        let stackView = self.stackedTitleView.subviews.first as? UIStackView
        #expect(stackView != nil)
        #expect(stackView?.arrangedSubviews.count == 2)
        #expect(stackView?.arrangedSubviews.first === self.stackedTitleView.titleLabel)
        #expect(stackView?.arrangedSubviews.last === self.stackedTitleView.subtitleLabel)
    }
    
    @Test func `Title and subtitle can be set`() {
        stackedTitleView.titleLabel.text = "Test Title"
        stackedTitleView.subtitleLabel.text = "Test Subtitle"
        
        #expect(self.stackedTitleView.titleLabel.text == "Test Title")
        #expect(self.stackedTitleView.subtitleLabel.text == "Test Subtitle")
    }
}
