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

@MainActor
@Suite(.serialized)
final class FeatureFlagsTests {
    private var defaults: UserDefaults!

    init() {
        defaults = UserDefaults(suiteName: "FeatureFlagsTests")!
        defaults.removePersistentDomain(forName: "FeatureFlagsTests")
    }

    @Test func `New stop page defaults to enabled`() {
        #expect(FeatureFlags.isNewStopPageEnabled(userDefaults: defaults))
    }

    @Test func `New stop page respects explicit false`() {
        defaults.set(false, forKey: FeatureFlags.useNewStopPageKey)
        #expect(!FeatureFlags.isNewStopPageEnabled(userDefaults: defaults))
    }

    @Test func `New stop page respects explicit true`() {
        defaults.set(true, forKey: FeatureFlags.useNewStopPageKey)
        #expect(FeatureFlags.isNewStopPageEnabled(userDefaults: defaults))
    }
}
