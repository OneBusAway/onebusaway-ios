//
//  OnboardingStepStoreTests.swift
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
final class OnboardingStepStoreTests {
    private let userDefaults: UserDefaults
    private let store: OnboardingStepStore

    /// `nonisolated` so `deinit` can read it without hopping to the main actor.
    private nonisolated let suiteName: String

    init() {
        suiteName = "OnboardingStepStoreTests-\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)!
        store = OnboardingStepStore(userDefaults: userDefaults)
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    @Test func `Unseen step has version zero`() {
        #expect(store.seenVersion(of: .notifications) == 0)
        #expect(store.isEmpty)
    }

    @Test func `Mark seen round trips through user defaults`() {
        store.markSeen(.welcome, version: 1)
        #expect(store.seenVersion(of: .welcome) == 1)
        #expect(!store.isEmpty)

        // A second store over the same defaults sees the same data.
        let rehydrated = OnboardingStepStore(userDefaults: userDefaults)
        #expect(rehydrated.seenVersion(of: .welcome) == 1)
    }

    @Test func `Mark seen never lowers version`() {
        store.markSeen(.location, version: 3)
        store.markSeen(.location, version: 1)
        #expect(store.seenVersion(of: .location) == 3)
    }

    @Test func `Backfill existing user marks legacy steps but not notifications`() {
        #expect(store.backfillIfNeeded(hasCurrentRegion: true))
        #expect(store.seenVersion(of: .welcome) == 1)
        #expect(store.seenVersion(of: .location) == 1)
        #expect(store.seenVersion(of: .region) == 1)
        #expect(store.seenVersion(of: .done) == 1)
        #expect(store.seenVersion(of: .notifications) == 0)
        #expect(store.seenVersion(of: .migration) == 0)
    }

    @Test func `Backfill new user does nothing`() {
        #expect(!store.backfillIfNeeded(hasCurrentRegion: false))
        #expect(store.isEmpty)
    }

    @Test func `Backfill non empty store never runs again`() {
        store.markSeen(.welcome, version: 1)
        #expect(!store.backfillIfNeeded(hasCurrentRegion: true))
        #expect(store.seenVersion(of: .region) == 0)
    }
}
