//
//  HoverBarTests.swift
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
final class HoverBarTests {

    // MARK: - HoverBarPassThroughView Tests

    @Test func hoverBarPassThroughViewDefaultInitialization() {
        let view = HoverBarPassThroughView()

        #expect(view.backgroundColor == .clear)
        #expect(view.showShadow == true)
        #expect(view.showCapInsetLines == false)
        #expect(view.subviews.count == 2)
    }

    @Test func hoverBarPassThroughViewShowShadowToggle() {
        let view = HoverBarPassThroughView(frame: CGRect(x: 0, y: 0, width: 80, height: 80))
        let shadowImageView = view.subviews.first as? UIImageView

        #expect(view.showShadow == true)
        #expect(shadowImageView?.isHidden == false)

        view.showShadow = false
        #expect(view.showShadow == false)
        #expect(shadowImageView?.isHidden == true)

        view.showShadow = true
        #expect(view.showShadow == true)
        #expect(shadowImageView?.isHidden == false)
    }

    @Test func hoverBarPassThroughViewShowCapInsetLinesToggle() {
        let view = HoverBarPassThroughView(frame: CGRect(x: 0, y: 0, width: 80, height: 80))
        let shadowImageView = view.subviews.first as? UIImageView
        let initialImage = shadowImageView?.image

        #expect(view.showCapInsetLines == false)
        #expect(initialImage != nil)

        view.showCapInsetLines = true
        #expect(view.showCapInsetLines == true)
        #expect(shadowImageView?.image !== initialImage)

        let capInsetLinesImage = shadowImageView?.image
        view.showCapInsetLines = false
        #expect(view.showCapInsetLines == false)
        #expect(shadowImageView?.image !== capInsetLinesImage)
    }

    // MARK: - HoverBar Tests

    @Test func hoverBarInitializationAndStackViewLayout() {
        let hoverBar = HoverBar(frame: CGRect(x: 0, y: 0, width: 44, height: 150))

        #expect(hoverBar.stackView.axis == .vertical)
        #expect(hoverBar.stackView.distribution == .fill)
        #expect(hoverBar.stackView.alignment == .fill)
        #expect(hoverBar.stackView.spacing == 2)
        #expect(hoverBar.stackView.translatesAutoresizingMaskIntoConstraints == false)
        #expect(hoverBar.contentView.subviews.contains(hoverBar.stackView))
    }

    // MARK: - HoverBarSeparator Tests

    @Test func hoverBarSeparatorDefaultProperties() {
        let separator = HoverBarSeparator(frame: .zero)

        #expect(separator.isAccessibilityElement == false)
        #expect(separator.backgroundColor == ThemeColors.shared.separator)
        #expect(separator.intrinsicContentSize.width == UIView.noIntrinsicMetric)
        #expect(separator.intrinsicContentSize.height > 0)
    }

    @Test func hoverBarSeparatorAccessibilityCannotBeOverridden() {
        let separator = HoverBarSeparator()
        separator.isAccessibilityElement = true

        #expect(separator.isAccessibilityElement == false)
    }

    @Test func hoverBarSeparatorIntrinsicContentSizeMatchesScale() {
        let separator = HoverBarSeparator(frame: CGRect(x: 0, y: 0, width: 44, height: 1))
        let expectedHeight = 1.0 / separator.traitCollection.displayScale

        #expect(separator.intrinsicContentSize.width == UIView.noIntrinsicMetric)
        #expect(separator.intrinsicContentSize.height == expectedHeight)
    }

    @Test func hoverBarPassThroughViewConvenienceInit() {
        let view = HoverBarPassThroughView()
        #expect(view.frame == .zero)
        #expect(view.subviews.count == 2)
    }
}
