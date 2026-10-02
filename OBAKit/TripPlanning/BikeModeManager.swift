//
//  BikeModeManager.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import HealthKit
import OBAKitCore

/// Resolves the user's cycling speed from HealthKit (if authorized) or falls back to
/// `BikeSpeed.defaultMetersPerSecond`. Does not own whether Bike Mode itself is enabled —
/// that's `UserDataStore.bikeModeEnabled`, set directly by the Settings UI. This manager only
/// owns `bikeSpeedMetersPerSecond` / `bikeSpeedSource`.
@MainActor
final class BikeModeManager {
    private let healthKit: BikeSpeedHealthKitProviding
    private let userDataStore: UserDataStore

    /// Bumped every time the user opts out of HealthKit so a sync that started earlier
    /// cannot write `.healthKit` back over the `.manual` the opt-out persisted (#1458.3).
    private var syncGeneration = 0

    init(userDataStore: UserDataStore, healthKit: BikeSpeedHealthKitProviding = HKHealthStoreBikeSpeedProvider()) {
        self.userDataStore = userDataStore
        self.healthKit = healthKit
    }

    /// Invalidates any sync still in flight. Call it before persisting a HealthKit opt-out
    /// so the stale sync's trailing write is abandoned instead of resurrecting `.healthKit`.
    func cancelPendingSync() {
        syncGeneration += 1
    }

    /// Requests HealthKit authorization and attempts to sync the average cycling speed.
    ///
    /// Apple's HealthKit privacy model does not surface read-permission denials: the
    /// authorization request succeeds even when the user taps "Don't Allow", and a
    /// subsequent query just returns no samples. To avoid leaving the source stuck on
    /// HealthKit for a denying user, success here is defined as "actually retrieved a usable
    /// sample". A user who genuinely granted access but has no recent cycling-speed samples
    /// (e.g. no Apple Watch) is also routed to `.manual` — that's intentional.
    ///
    /// A sync invalidated by `cancelPendingSync()` (the user opted out while it was in
    /// flight) abandons without touching the store, so the opt-out wins.
    @discardableResult
    func requestHealthKitAuthorizationAndSync() async -> Bool {
        let generation = syncGeneration

        guard healthKit.isAvailable else {
            guard generation == syncGeneration else { return false }
            userDataStore.bikeSpeedSource = .manual
            return false
        }

        do {
            try await healthKit.requestAuthorization()
        } catch {
            Logger.error("BikeModeManager: HealthKit requestAuthorization failed: \(error)")
            guard generation == syncGeneration else { return false }
            userDataStore.bikeSpeedSource = .manual
            return false
        }

        guard generation == syncGeneration else { return false }

        let didSync = await syncAverageBikeSpeed(expectedGeneration: generation)
        if !didSync, generation == syncGeneration {
            userDataStore.bikeSpeedSource = .manual
        }
        return didSync
    }

    /// Passive refresh used at launch when the user already opted into HealthKit previously.
    /// Updates `bikeSpeedMetersPerSecond` if a fresh sample is available, but never flips
    /// `bikeSpeedSource` to `.manual` — an idle user keeps their previously-synced value and
    /// their stated intent. Only the active sync path in Settings can downgrade the source.
    func refreshFromHealthKitIfPossible() async {
        guard healthKit.isAvailable else { return }
        let generation = syncGeneration
        await syncAverageBikeSpeed(expectedGeneration: generation)
    }

    /// Fetches the average cycling speed and writes it to the store if it's in `BikeSpeed.validRange`.
    /// Returns `true` on a successful write; otherwise leaves the stored speed and source untouched
    /// and returns `false`. Callers decide how to react to a `false` result.
    /// When `expectedGeneration` no longer matches (opt-out raced the sync), the write is
    /// abandoned and `false` is returned without touching the store.
    @discardableResult
    private func syncAverageBikeSpeed(expectedGeneration: Int? = nil) async -> Bool {
        guard let mps = await healthKit.fetchAverageBikeSpeed(),
              BikeSpeed.validRange.contains(mps)
        else {
            return false
        }

        if let expectedGeneration, expectedGeneration != syncGeneration {
            return false
        }

        userDataStore.bikeSpeedMetersPerSecond = mps
        userDataStore.bikeSpeedSource = .healthKit
        return true
    }
}
