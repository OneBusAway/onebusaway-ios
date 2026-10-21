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

    @Test func hoverBarPassThroughViewContentViewHierarchy() {
        let view = HoverBarPassThroughView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let contentView = view.contentView

        let testButton = UIButton(type: .system)
        testButton.setTitle("Test Action", for: .normal)
        contentView.addSubview(testButton)

        #expect(contentView.subviews.contains(testButton))
        #expect(contentView.subviews.count == 1)
    }

    @Test func hoverBarPassThroughViewShowShadowToggle() {
        let view = HoverBarPassThroughView(frame: CGRect(x: 0, y: 0, width: 80, height: 80))

        #expect(view.showShadow == true)

        view.showShadow = false
        #expect(view.showShadow == false)

        view.showShadow = true
        #expect(view.showShadow == true)
    }

    @Test func hoverBarPassThroughViewShowCapInsetLinesToggle() {
        let view = HoverBarPassThroughView(frame: CGRect(x: 0, y: 0, width: 80, height: 80))

        #expect(view.showCapInsetLines == false)

        view.showCapInsetLines = true
        #expect(view.showCapInsetLines == true)

        view.showCapInsetLines = false
        #expect(view.showCapInsetLines == false)
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

    @Test func hoverBarArrangedSubviewsLifecycle() {
        let hoverBar = HoverBar(frame: CGRect(x: 0, y: 0, width: 44, height: 120))

        let topButton = UIButton(type: .custom)
        let bottomButton = UIButton(type: .custom)
        let separator = HoverBarSeparator()

        hoverBar.stackView.addArrangedSubview(topButton)
        hoverBar.stackView.addArrangedSubview(separator)
        hoverBar.stackView.addArrangedSubview(bottomButton)

        #expect(hoverBar.stackView.arrangedSubviews.count == 3)
        #expect(hoverBar.stackView.arrangedSubviews[0] === topButton)
        #expect(hoverBar.stackView.arrangedSubviews[1] === separator)
        #expect(hoverBar.stackView.arrangedSubviews[2] === bottomButton)
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

    @Test func hoverBarPassThroughViewConvenienceInit() {
        let view = HoverBarPassThroughView()
        #expect(view.frame == .zero)
        #expect(view.subviews.count == 2)
    }
}
