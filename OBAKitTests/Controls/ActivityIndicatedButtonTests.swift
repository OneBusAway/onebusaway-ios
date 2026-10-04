//
//  ActivityIndicatedButtonTests.swift
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
final class ActivityIndicatedButtonTests {

    @Test func testConfigurationInitialization() {
        var actionFired = false
        let config = ActivityIndicatedButton.Configuration(
            text: "Tap Me",
            largeContentImage: nil,
            showsActivityIndicatorOnTap: true
        ) {
            actionFired = true
        }

        #expect(config.text == "Tap Me")
        #expect(config.largeContentImage == nil)
        #expect(config.showsActivityIndicatorOnTap == true)

        let buttonView = ActivityIndicatedButton(config: config)
        buttonView.buttonDidTap(UIButton())

        #expect(actionFired == true)
    }

    @Test func testConfigurationEquality() {
        let image1 = UIImage(systemName: "star")
        let image2 = UIImage(systemName: "heart")

        let config1 = ActivityIndicatedButton.Configuration(
            text: "Refresh",
            largeContentImage: image1,
            showsActivityIndicatorOnTap: true,
            action: {}
        )

        let config2 = ActivityIndicatedButton.Configuration(
            text: "Refresh",
            largeContentImage: image1,
            showsActivityIndicatorOnTap: true,
            action: {}
        )

        let config3 = ActivityIndicatedButton.Configuration(
            text: "Different",
            largeContentImage: image1,
            showsActivityIndicatorOnTap: true,
            action: {}
        )

        let config4 = ActivityIndicatedButton.Configuration(
            text: "Refresh",
            largeContentImage: image1,
            showsActivityIndicatorOnTap: false,
            action: {}
        )

        let config5 = ActivityIndicatedButton.Configuration(
            text: "Refresh",
            largeContentImage: image2,
            showsActivityIndicatorOnTap: true,
            action: {}
        )

        #expect(config1 == config2)
        #expect(config1 != config3)
        #expect(config1 != config4)
        #expect(config1 != config5)
    }

    @Test func testConfigurationEqualityIgnoresActionClosure() {
        let config1 = ActivityIndicatedButton.Configuration(
            text: "Same",
            largeContentImage: nil,
            showsActivityIndicatorOnTap: true,
            action: { print("Action 1") }
        )

        let config2 = ActivityIndicatedButton.Configuration(
            text: "Same",
            largeContentImage: nil,
            showsActivityIndicatorOnTap: true,
            action: { print("Action 2") }
        )

        // Closures are fundamentally un-equatable, so our custom == deliberately ignores them.
        #expect(config1 == config2)
    }

    @Test func testInitializationWithConfig() {
        let config = ActivityIndicatedButton.Configuration(
            text: "Start",
            largeContentImage: nil,
            showsActivityIndicatorOnTap: true,
            action: {}
        )

        let buttonView = ActivityIndicatedButton(config: config)
        #expect(buttonView.config == config)
    }

    @Test func testViewVisibilityWhenConfigIsNil() {
        let buttonView = ActivityIndicatedButton(config: nil)
        #expect(buttonView.isHidden == true)

        let config = ActivityIndicatedButton.Configuration(
            text: "Test",
            largeContentImage: nil,
            action: {}
        )
        buttonView.config = config

        // Call configureView() directly to avoid test flakiness from DispatchQueue.main.async
        buttonView.configureView()

        #expect(buttonView.isHidden == false)
    }

    @Test func testShowAndHideActivityIndicator() {
        let config = ActivityIndicatedButton.Configuration(
            text: "Test",
            largeContentImage: nil,
            action: {}
        )
        let buttonView = ActivityIndicatedButton(config: config)

        buttonView.showActivityIndicator()

        #expect(buttonView.button.isHidden == true)
        #expect(buttonView.chevron.isHidden == true)
        #expect(buttonView.activityIndicator.isAnimating == true)

        buttonView.hideActivityIndicator()

        #expect(buttonView.button.isHidden == false)
        #expect(buttonView.chevron.isHidden == false)
        #expect(buttonView.activityIndicator.isAnimating == false)
    }

    @Test func testPrepareForReuse() {
        let config = ActivityIndicatedButton.Configuration(
            text: "Test",
            largeContentImage: nil,
            action: {}
        )
        let buttonView = ActivityIndicatedButton(config: config)

        // Ensure configureView has run
        buttonView.configureView()

        buttonView.showActivityIndicator()
        buttonView.prepareForReuse()

        // Ensure configureView has run after config = nil
        buttonView.configureView()

        #expect(buttonView.config == nil)
        #expect(buttonView.isHidden == true)
        #expect(buttonView.activityIndicator.isAnimating == false)
        #expect(buttonView.button.isHidden == false)
        #expect(buttonView.chevron.isHidden == false)
    }
}
