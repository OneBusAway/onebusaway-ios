//
//  AwesomeSpotlightViewTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import Testing
import OBAKitCore
@testable import OBAKit

@MainActor
@Suite(.serialized)
final class AwesomeSpotlightViewTests {

    @Test func testAwesomeSpotlightViewConvenienceInitConfiguresState() {
        let frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        let spotlight1 = AwesomeSpotlight(rect: CGRect(x: 10, y: 10, width: 50, height: 30), attributedText: NSAttributedString(string: "Step 1"))
        let spotlight2 = AwesomeSpotlight(rect: CGRect(x: 10, y: 100, width: 50, height: 30), attributedText: NSAttributedString(string: "Step 2"))

        let view = AwesomeSpotlightView(frame: frame, spotlight: [spotlight1, spotlight2])

        #expect(view.spotlightsArray.count == 2)
        #expect(view.currentIndex == 0)
        #expect(!view.isShowed)
        #expect(view.frame == frame)
    }

    @Test func testCustomSpotlightMaskColorUpdatesLayer() throws {
        let frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        let spotlight = AwesomeSpotlight(rect: CGRect(x: 10, y: 10, width: 50, height: 30), attributedText: NSAttributedString(string: "Step 1"))
        let view = AwesomeSpotlightView(frame: frame, spotlight: [spotlight])

        let customColor = UIColor.red
        view.spotlightMaskColor = customColor

        let shapeLayer = try #require(view.layer.sublayers?.compactMap { $0 as? CAShapeLayer }.first)
        #expect(shapeLayer.fillColor == customColor.cgColor)
    }

    @Test func testSkipSpotlightTransitionsToDoneTitleOnLastStep() {
        let frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        let spotlight1 = AwesomeSpotlight(rect: CGRect(x: 10, y: 10, width: 50, height: 30), attributedText: NSAttributedString(string: "Step 1"))
        let spotlight2 = AwesomeSpotlight(rect: CGRect(x: 10, y: 100, width: 50, height: 30), attributedText: NSAttributedString(string: "Step 2"))
        let view = AwesomeSpotlightView(frame: frame, spotlight: [spotlight1, spotlight2])

        view.skipButtonModel.isEnable = true
        view.start()

        let skipButtonBefore = view.subviews.compactMap { $0 as? UIButton }.first
        #expect(skipButtonBefore?.title(for: []) == Strings.skip)

        view.userDidTap(UITapGestureRecognizer())

        let skipButtonAfter = view.subviews.compactMap { $0 as? UIButton }.first
        #expect(skipButtonAfter?.title(for: .normal) == Strings.done)
    }
}
