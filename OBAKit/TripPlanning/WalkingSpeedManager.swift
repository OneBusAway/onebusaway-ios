//
//  WalkingSpeedManager.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import HealthKit
import OBAKitCore

/// Resolves the user's walking speed from HealthKit (if authorized) or falls back to a user preference.
@MainActor
final class WalkingSpeedManager {
    private let healthKit: WalkingSpeedHealthKitProviding
    private let userDataStore: UserDataStore

    init(userDataStore: UserDataStore, healthKit: WalkingSpeedHealthKitProviding = HKHealthStoreWalkingSpeedProvider()) {
        self.userDataStore = userDataStore
        self.healthKit = healthKit
    }

    /// Requests HealthKit authorization and attempts to sync the latest walking speed.
    ///
    /// Apple's HealthKit privacy model does not surface read-permission denials: the
    /// authorization request succeeds even when the user taps "Don't Allow", and a
    /// subsequent query just returns no samples. To avoid leaving the toggle stuck ON
    /// for a denying user, success here is defined as "actually retrieved a usable
    /// sample". A user who genuinely granted access but has no recent walking-speed
    /// samples (e.g. no Apple Watch) is also routed to `.manual` — that's intentional.
    @discardableResult
    func requestHealthKitAuthorizationAndSync() async -> Bool {
        guard healthKit.isAvailable else {
            userDataStore.walkingSpeedSource = .manual
            return false
        }

        do {
            try await healthKit.requestAuthorization()
        } catch {
            Logger.error("WalkingSpeedManager: HealthKit requestAuthorization failed: \(error)")
            userDataStore.walkingSpeedSource = .manual
            return false
        }

        let didSync = await syncLatestWalkingSpeed()
        if !didSync {
            userDataStore.walkingSpeedSource = .manual
        }
        return didSync
    }

    /// Passive refresh used at launch when the user already opted into HealthKit previously.
    /// Updates `walkingSpeedMetersPerSecond` if a fresh sample is available, but never
    /// flips `walkingSpeedSource` to `.manual` — an idle user (e.g. left their Apple Watch
    /// at home for a month) keeps their previously-synced value and their stated intent.
    /// Only the active toggle-on path in Settings can downgrade the source.
    func refreshFromHealthKitIfPossible() async {
        guard healthKit.isAvailable else { return }
        await syncLatestWalkingSpeed()
    }

    /// Fetches the latest walking-speed sample and writes it to the store if it's in `WalkingSpeed.validRange`.
    /// Returns `true` on a successful write; otherwise leaves the stored speed and source untouched
    /// and returns `false`. Callers decide how to react to a `false` result.
    @discardableResult
    private func syncLatestWalkingSpeed() async -> Bool {
        guard let mps = await healthKit.fetchLatestWalkingSpeed(),
              WalkingSpeed.validRange.contains(mps)
        else {
            return false
        }

        userDataStore.walkingSpeedMetersPerSecond = mps
        userDataStore.walkingSpeedSource = .healthKit
        return true
    }
}
