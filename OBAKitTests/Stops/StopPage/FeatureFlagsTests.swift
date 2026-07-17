//
//  FeatureFlagsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//
import XCTest
@testable import OBAKitCore

@MainActor
final class FeatureFlagsTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        defaults = UserDefaults(suiteName: "FeatureFlagsTests")!
        defaults.removePersistentDomain(forName: "FeatureFlagsTests")
    }

    func test_newStopPage_defaultsToEnabled() {
        XCTAssertTrue(FeatureFlags.isNewStopPageEnabled(userDefaults: defaults))
    }

    func test_newStopPage_respectsExplicitFalse() {
        defaults.set(false, forKey: FeatureFlags.useNewStopPageKey)
        XCTAssertFalse(FeatureFlags.isNewStopPageEnabled(userDefaults: defaults))
    }

    func test_newStopPage_respectsExplicitTrue() {
        defaults.set(true, forKey: FeatureFlags.useNewStopPageKey)
        XCTAssertTrue(FeatureFlags.isNewStopPageEnabled(userDefaults: defaults))
    }
}
