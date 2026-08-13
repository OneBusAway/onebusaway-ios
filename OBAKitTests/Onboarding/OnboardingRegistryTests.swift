//
//  OnboardingRegistryTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit

@MainActor
@Suite(.serialized)
final class OnboardingRegistryTests {
    private let store: OnboardingStepStore

    /// `nonisolated` so `deinit` can read it without hopping to the main actor.
    private nonisolated let suiteName: String

    init() {
        suiteName = "OnboardingRegistryTests-\(UUID().uuidString)"
        store = OnboardingStepStore(userDefaults: UserDefaults(suiteName: suiteName)!)
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
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

    @Test func `New user gets full ordered flow`() {
        #expect(flowIDs(newUserEnvironment()) == [.welcome, .location, .region, .notifications, .done])
    }

    @Test func `Migrating user gets migration first`() {
        var env = newUserEnvironment()
        env.hasDataToMigrate = true
        env.shouldPerformMigration = true
        #expect(flowIDs(env) == [.migration, .welcome, .location, .region, .notifications, .done])
    }

    @Test func `Backfilled existing user gets exactly notifications`() {
        store.backfillIfNeeded(hasCurrentRegion: true)
        #expect(flowIDs(newUserEnvironment()) == [.notifications])
    }

    @Test func `No push provider hides notifications step`() {
        var env = newUserEnvironment()
        env.isPushServiceConfigured = false
        #expect(flowIDs(env) == [.welcome, .location, .region, .done])
    }

    @Test func `Determined notification permission hides notifications step`() {
        var env = newUserEnvironment()
        env.notificationAuthorizationDetermined = true
        #expect(flowIDs(env) == [.welcome, .location, .region, .done])
    }

    @Test func `Determined location permission hides location step`() {
        var env = newUserEnvironment()
        env.locationAuthorizationDetermined = true
        #expect(flowIDs(env) == [.welcome, .region, .notifications, .done])
    }

    @Test func `Version bump reshows only that step`() {
        store.backfillIfNeeded(hasCurrentRegion: true)
        store.markSeen(.notifications, version: 1)
        let env = newUserEnvironment()

        #expect(flowIDs(env) == [])

        // Simulate a future release bumping the location step to v2.
        let bumped = OnboardingRegistry.steps.map { step in
            step.id == .location
                ? OnboardingStep(id: step.id, weight: step.weight, version: 2, tracksSeen: step.tracksSeen, isEligible: step.isEligible)
                : step
        }
        let flow = OnboardingRegistry.flow(steps: bumped, environment: env, store: store)
        #expect(flow.map(\.id) == [.location])
    }

    @Test func `Migration ignores seen state`() {
        var env = newUserEnvironment()
        env.hasDataToMigrate = true
        env.shouldPerformMigration = true
        store.markSeen(.migration, version: 99)
        #expect(flowIDs(env).contains(.migration))
    }

    @Test func `Allow once reversion step seen so not reshown`() {
        // "Allow Once" reverts location auth to .notDetermined after use, but a seen step stays hidden.
        var env = newUserEnvironment()
        env.locationAuthorizationDetermined = false
        store.markSeen(.location, version: 1)
        #expect(!flowIDs(env).contains(.location))
    }

    @Test func `Registry step IDs and weights are unique`() {
        #expect(Set(OnboardingRegistry.steps.map(\.id)).count == OnboardingRegistry.steps.count)
        #expect(Set(OnboardingRegistry.steps.map(\.weight)).count == OnboardingRegistry.steps.count)
    }

    @Test func `Flow sorts by weight not declaration order`() {
        let reversed = Array(OnboardingRegistry.steps.reversed())
        let flow = OnboardingRegistry.flow(steps: reversed, environment: newUserEnvironment(), store: store)
        #expect(flow.map(\.id) == [.welcome, .location, .region, .notifications, .done])
    }
}
