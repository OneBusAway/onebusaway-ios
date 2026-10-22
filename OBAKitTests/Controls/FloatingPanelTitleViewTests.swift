//
//  FloatingPanelTitleViewTests.swift
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
final class FloatingPanelTitleViewTests {

    @Test func defaultInitializationProperties() {
        let titleView = FloatingPanelTitleView(frame: CGRect(x: 0, y: 0, width: 320, height: 80))

        #expect(titleView.titleLabel.numberOfLines == 0)
        #expect(titleView.titleLabel.font == UIFont.preferredFont(forTextStyle: .title1).bold)
        #expect(titleView.titleLabel.contentHuggingPriority(for: .horizontal) == .defaultLow)
        #expect(titleView.titleLabel.contentCompressionResistancePriority(for: .horizontal) == .required)

        #expect(titleView.subtitleLabel.numberOfLines == 0)
        #expect(titleView.subtitleLabel.font == UIFont.preferredFont(forTextStyle: .body))

        #expect(titleView.directionalLayoutMargins.top == ThemeMetrics.padding)
        #expect(titleView.directionalLayoutMargins.leading == ThemeMetrics.controllerMargin)
        #expect(titleView.directionalLayoutMargins.bottom == ThemeMetrics.padding)
        #expect(titleView.directionalLayoutMargins.trailing == ThemeMetrics.controllerMargin)

        #expect(titleView.subviews.count == 1)
        #expect(titleView.subviews.first is UIStackView)
    }

    @Test func closeButtonConfigurationAndHierarchy() {
        let titleView = FloatingPanelTitleView()

        #expect(titleView.closeButton.isUserInteractionEnabled == true)
        #expect(titleView.closeButton.superview != nil)

        // Verify closeButton is contained within the top stack view hierarchy
        let topStack = titleView.subviews.first as? UIStackView
        #expect(topStack?.arrangedSubviews.count == 2)
        #expect(titleView.closeButton.isDescendant(of: titleView))
    }
}
