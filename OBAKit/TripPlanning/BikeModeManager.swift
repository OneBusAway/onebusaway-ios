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

    init(userDataStore: UserDataStore, healthKit: BikeSpeedHealthKitProviding = HKHealthStoreBikeSpeedProvider()) {
        self.userDataStore = userDataStore
        self.healthKit = healthKit
    }

    /// Requests HealthKit authorization and attempts to sync the latest cycling speed.
    ///
    /// Apple's HealthKit privacy model does not surface read-permission denials: the
    /// authorization request succeeds even when the user taps "Don't Allow", and a
    /// subsequent query just returns no samples. To avoid leaving the source stuck on
    /// HealthKit for a denying user, success here is defined as "actually retrieved a usable
    /// sample". A user who genuinely granted access but has no recent cycling-speed samples
    /// (e.g. no Apple Watch) is also routed to `.manual` — that's intentional.
    @discardableResult
    func requestHealthKitAuthorizationAndSync() async -> Bool {
        guard healthKit.isAvailable else {
            userDataStore.bikeSpeedSource = .manual
            return false
        }

        do {
            try await healthKit.requestAuthorization()
        } catch {
            Logger.error("BikeModeManager: HealthKit requestAuthorization failed: \(error)")
            userDataStore.bikeSpeedSource = .manual
            return false
        }

        let didSync = await syncLatestBikeSpeed()
        if !didSync {
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
        await syncLatestBikeSpeed()
    }

    /// Fetches the latest cycling-speed sample and writes it to the store if it's in `BikeSpeed.validRange`.
    /// Returns `true` on a successful write; otherwise leaves the stored speed and source untouched
    /// and returns `false`. Callers decide how to react to a `false` result.
    @discardableResult
    private func syncLatestBikeSpeed() async -> Bool {
        guard let mps = await healthKit.fetchLatestBikeSpeed(),
              BikeSpeed.validRange.contains(mps)
        else {
            return false
        }

        userDataStore.bikeSpeedMetersPerSecond = mps
        userDataStore.bikeSpeedSource = .healthKit
        return true
    }
}
