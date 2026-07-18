//
//  OnboardingStepStore.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Identifies each onboarding step. The raw value is the persistence key, so never rename cases.
public enum OnboardingStepID: String, CaseIterable, Sendable {
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
public final class OnboardingStepStore {
    static let userDefaultsKey = "OBAOnboardingSeenStepVersions"

    /// Steps that conceptually existed before the registry shipped. An existing user
    /// (identified by having a selected region) is treated as having seen these at v1,
    /// so the only step they match is whatever is *not* in this set — initially `.notifications`.
    /// Future steps need no change here: they are simply never backfilled.
    static let backfilledStepIDs: [OnboardingStepID] = [.welcome, .location, .region, .done]

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    private var seenVersions: [String: Int] {
        get { (userDefaults.dictionary(forKey: Self.userDefaultsKey) as? [String: Int]) ?? [:] }
        set { userDefaults.set(newValue, forKey: Self.userDefaultsKey) }
    }

    public var isEmpty: Bool {
        seenVersions.isEmpty
    }

    public func seenVersion(of id: OnboardingStepID) -> Int {
        seenVersions[id.rawValue] ?? 0
    }

    public func markSeen(_ id: OnboardingStepID, version: Int) {
        guard version > seenVersion(of: id) else { return }
        seenVersions[id.rawValue] = version
    }

    /// One-time seeding for users who onboarded before the registry existed.
    /// Runs only when the store has never recorded anything and a region is already selected.
    @discardableResult
    public func backfillIfNeeded(hasCurrentRegion: Bool) -> Bool {
        guard isEmpty, hasCurrentRegion else { return false }
        for id in Self.backfilledStepIDs {
            markSeen(id, version: 1)
        }
        return true
    }
}
