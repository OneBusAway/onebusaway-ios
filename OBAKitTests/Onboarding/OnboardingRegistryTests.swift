//
//  OnboardingRegistryTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
@testable import OBAKit

@MainActor
final class OnboardingRegistryTests: XCTestCase {
    private var store: OnboardingStepStore!

    override func setUp() {
        super.setUp()
        store = OnboardingStepStore(userDefaults: UserDefaults(suiteName: "OnboardingRegistryTests-\(UUID().uuidString)")!)
    }

    /// Environment helper: a brand-new install with everything available.
    private func newUserEnvironment() -> OnboardingEnvironment {
        OnboardingEnvironment(
            hasDataToMigrate: false,
            shouldPerformMigration: false,
            hasCurrentRegion: false,
            locationAuthorizationDetermined: false,
            notificationAuthorizationDetermined: false,
            isPushServiceConfigured: true)
    }

    private func flowIDs(_ environment: OnboardingEnvironment) -> [OnboardingStepID] {
        OnboardingRegistry.flow(environment: environment, store: store).map(\.id)
    }

    func test_newUser_getsFullOrderedFlow() {
        XCTAssertEqual(flowIDs(newUserEnvironment()), [.welcome, .location, .region, .notifications, .done])
    }

    func test_migratingUser_getsMigrationFirst() {
        var env = newUserEnvironment()
        env.hasDataToMigrate = true
        env.shouldPerformMigration = true
        XCTAssertEqual(flowIDs(env), [.migration, .welcome, .location, .region, .notifications, .done])
    }

    func test_backfilledExistingUser_getsExactlyNotifications() {
        var env = newUserEnvironment()
        env.hasCurrentRegion = true
        store.backfillIfNeeded(hasCurrentRegion: true)
        XCTAssertEqual(flowIDs(env), [.notifications])
    }

    func test_noPushProvider_hidesNotificationsStep() {
        var env = newUserEnvironment()
        env.isPushServiceConfigured = false
        XCTAssertEqual(flowIDs(env), [.welcome, .location, .region, .done])
    }

    func test_determinedNotificationPermission_hidesNotificationsStep() {
        var env = newUserEnvironment()
        env.notificationAuthorizationDetermined = true
        XCTAssertEqual(flowIDs(env), [.welcome, .location, .region, .done])
    }

    func test_determinedLocationPermission_hidesLocationStep() {
        var env = newUserEnvironment()
        env.locationAuthorizationDetermined = true
        XCTAssertEqual(flowIDs(env), [.welcome, .region, .notifications, .done])
    }

    func test_versionBump_reshowsOnlyThatStep() {
        store.backfillIfNeeded(hasCurrentRegion: true)
        store.markSeen(.notifications, version: 1)
        var env = newUserEnvironment()
        env.hasCurrentRegion = true

        XCTAssertEqual(flowIDs(env), [])

        // Simulate a future release bumping the location step to v2.
        let bumped = OnboardingRegistry.steps.map { step in
            step.id == .location
                ? OnboardingStep(id: step.id, weight: step.weight, version: 2, tracksSeen: step.tracksSeen, isEligible: step.isEligible)
                : step
        }
        let flow = OnboardingRegistry.flow(steps: bumped, environment: env, store: store)
        XCTAssertEqual(flow.map(\.id), [.location])
    }

    func test_migration_ignoresSeenState() {
        var env = newUserEnvironment()
        env.hasDataToMigrate = true
        env.shouldPerformMigration = true
        store.markSeen(.migration, version: 99)
        XCTAssertTrue(flowIDs(env).contains(.migration))
    }

    func test_allowOnceReversion_stepSeenSoNotReshown() {
        // "Allow Once" reverts location auth to .notDetermined after use, but a seen step stays hidden.
        var env = newUserEnvironment()
        env.locationAuthorizationDetermined = false
        store.markSeen(.location, version: 1)
        XCTAssertFalse(flowIDs(env).contains(.location))
    }
}
