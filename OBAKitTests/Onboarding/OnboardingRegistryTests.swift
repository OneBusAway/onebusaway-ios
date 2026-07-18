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
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        let name = "OnboardingRegistryTests-\(UUID().uuidString)"
        await MainActor.run {
            suiteName = name
            store = OnboardingStepStore(userDefaults: UserDefaults(suiteName: name)!)
        }
    }

    override func tearDown() async throws {
        let name = await MainActor.run { suiteName }
        UserDefaults().removePersistentDomain(forName: name!)
        try await super.tearDown()
    }

    /// Environment helper: a brand-new install with everything available.
    private func newUserEnvironment() -> OnboardingEnvironment {
        OnboardingEnvironment(
            hasDataToMigrate: false,
            shouldPerformMigration: false,
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
        store.backfillIfNeeded(hasCurrentRegion: true)
        XCTAssertEqual(flowIDs(newUserEnvironment()), [.notifications])
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
        let env = newUserEnvironment()

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

    func test_registry_stepIDsAndWeightsAreUnique() {
        XCTAssertEqual(Set(OnboardingRegistry.steps.map(\.id)).count, OnboardingRegistry.steps.count)
        XCTAssertEqual(Set(OnboardingRegistry.steps.map(\.weight)).count, OnboardingRegistry.steps.count)
    }

    func test_flow_sortsByWeightNotDeclarationOrder() {
        let reversed = Array(OnboardingRegistry.steps.reversed())
        let flow = OnboardingRegistry.flow(steps: reversed, environment: newUserEnvironment(), store: store)
        XCTAssertEqual(flow.map(\.id), [.welcome, .location, .region, .notifications, .done])
    }
}
