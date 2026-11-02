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

    @Test func testAwesomeSpotlightInitialization() {
        let rect = CGRect(x: 20, y: 50, width: 100, height: 40)
        let text = NSAttributedString(string: "Tap here to begin")
        let spotlight = AwesomeSpotlight(rect: rect, attributedText: text)

        #expect(spotlight.rect == rect)
        #expect(spotlight.attributedText.string == "Tap here to begin")
    }

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

    @Test func testCustomSpotlightMaskColorUpdatesLayer() {
        let view = AwesomeSpotlightView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let customColor = UIColor.red

        view.spotlightMaskColor = customColor
        #expect(view.spotlightMaskColor == customColor)
    }

    @Test func testSkipSpotlightTransitionsToDoneTitleOnLastStep() {
        let frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        let spotlight = AwesomeSpotlight(rect: CGRect(x: 10, y: 10, width: 50, height: 30), attributedText: NSAttributedString(string: "Step 1"))
        let view = AwesomeSpotlightView(frame: frame, spotlight: [spotlight])

        #expect(view.skipButtonModel.title == Strings.skip)
        #expect(view.skipButtonLastStepTitle == Strings.done)
    }
}
