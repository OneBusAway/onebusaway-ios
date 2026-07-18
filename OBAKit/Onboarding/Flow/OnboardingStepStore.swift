//
//  OnboardingStepStore.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// Identifies each onboarding step. The raw value is the persistence key, so never rename cases.
enum OnboardingStepID: String, CaseIterable, Sendable {
    case migration
    case welcome
    case location
    case region
    case notifications
    case done
}

/// Persists which onboarding steps a user has seen, and at what version.
///
/// A step is re-shown when its registry version exceeds the seen version. Steps mark
/// themselves seen at their own completion point (see `OnboardingFlowView`), not on display.
@MainActor
final class OnboardingStepStore {
    static let userDefaultsKey = "OBAOnboardingSeenStepVersions"

    /// Steps that conceptually existed before the registry shipped. An existing user
    /// (identified by having a selected region) is treated as having seen these at v1,
    /// so the only seen-tracked steps they can match are ones *not* in this set —
    /// initially `.notifications`. (Migration ignores the seen store entirely.)
    /// Future steps need no change here: they are simply never backfilled.
    static let backfilledStepIDs: [OnboardingStepID] = [.welcome, .location, .region, .done]

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    private var seenVersions: [String: Int] {
        get {
            guard let stored = userDefaults.dictionary(forKey: Self.userDefaultsKey) else { return [:] }
            guard let versions = stored as? [String: Int] else {
                Logger.warn("OnboardingStepStore: stored seen-versions value has an unexpected type; treating as empty")
                return [:]
            }
            return versions
        }
        set { userDefaults.set(newValue, forKey: Self.userDefaultsKey) }
    }

    var isEmpty: Bool {
        seenVersions.isEmpty
    }

    func seenVersion(of id: OnboardingStepID) -> Int {
        seenVersions[id.rawValue] ?? 0
    }

    func markSeen(_ id: OnboardingStepID, version: Int) {
        guard version > seenVersion(of: id) else { return }
        seenVersions[id.rawValue] = version
    }

    /// One-time seeding for users who onboarded before the registry existed.
    /// Runs only when the store has never recorded anything and a region is already selected.
    @discardableResult
    func backfillIfNeeded(hasCurrentRegion: Bool) -> Bool {
        guard isEmpty, hasCurrentRegion else { return false }
        var versions = seenVersions
        for id in Self.backfilledStepIDs {
            versions[id.rawValue] = 1
        }
        seenVersions = versions
        return true
    }
}
