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
        let config1 = ActivityIndicatedButton.Configuration(
            text: "Refresh",
            largeContentImage: nil,
            showsActivityIndicatorOnTap: true,
            action: {}
        )

        let config2 = ActivityIndicatedButton.Configuration(
            text: "Refresh",
            largeContentImage: nil,
            showsActivityIndicatorOnTap: true,
            action: {}
        )

        let config3 = ActivityIndicatedButton.Configuration(
            text: "Different",
            largeContentImage: nil,
            showsActivityIndicatorOnTap: true,
            action: {}
        )

        let config4 = ActivityIndicatedButton.Configuration(
            text: "Refresh",
            largeContentImage: nil,
            showsActivityIndicatorOnTap: false,
            action: {}
        )

        #expect(config1 == config2)
        #expect(config1 != config3)
        #expect(config1 != config4)
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
}
