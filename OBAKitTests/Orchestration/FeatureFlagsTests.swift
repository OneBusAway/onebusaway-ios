//
//  FeatureFlagsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

@Suite(.serialized)
final class FeatureFlagsTests {
    
    var userDefaults: UserDefaults!
    
    init() {
        // Create an ephemeral UserDefaults for isolated testing
        userDefaults = UserDefaults(suiteName: "org.opentransit.onebusaway-ios.FeatureFlagsTests")
        userDefaults.removePersistentDomain(forName: "org.opentransit.onebusaway-ios.FeatureFlagsTests")
    }

    @Test func `New stop page is enabled by default when untouched`() {
        // userDefaults has no entry for useNewStopPageKey initially
        let isEnabled = FeatureFlags.isNewStopPageEnabled(userDefaults: userDefaults)
        #expect(isEnabled == true)
    }

    @Test func `New stop page reflects explicitly disabled state`() {
        userDefaults.set(false, forKey: FeatureFlags.useNewStopPageKey)
        let isEnabled = FeatureFlags.isNewStopPageEnabled(userDefaults: userDefaults)
        #expect(isEnabled == false)
    }

    @Test func `New stop page reflects explicitly enabled state`() {
        userDefaults.set(true, forKey: FeatureFlags.useNewStopPageKey)
        let isEnabled = FeatureFlags.isNewStopPageEnabled(userDefaults: userDefaults)
        #expect(isEnabled == true)
    }
}