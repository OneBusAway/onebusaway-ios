//
//  BikeModeManager.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// Resolves the user's cycling speed from the app's speed provider (if it has one and is authorized) or falls back to
/// `BikeSpeed.defaultMetersPerSecond`. Does not own whether Bike Mode itself is enabled —
/// that's `UserDataStore.bikeModeEnabled`, set directly by the Settings UI. This manager only
/// owns `bikeSpeedMetersPerSecond` / `bikeSpeedSource`.
@MainActor
final class BikeModeManager {
    private let provider: (any SpeedProviding)?
    private let userDataStore: UserDataStore

    /// Bumped every time the user opts out of speed sync so a sync that started earlier
    /// cannot write `.synced` back over the `.manual` the opt-out persisted (#1458.3).
    private var syncGeneration = 0

    init(userDataStore: UserDataStore, provider: (any SpeedProviding)?) {
        self.userDataStore = userDataStore
        self.provider = provider
    }

    /// Leaves speed sync, abandoning any sync still in flight so it can't write `.synced`
    /// back over the `.manual` persisted here.
    /// Unlike walking there's no manual speed to snap to; the stored speed stays as it is.
    func stopSyncing() {
        syncGeneration += 1
        userDataStore.bikeSpeedSource = .manual
    }

    /// Requests the provider's authorization and attempts to sync the average cycling speed.
    ///
    /// The provider's privacy model does not surface read-permission denials: the
    /// authorization request succeeds even when the user taps "Don't Allow", and a
    /// subsequent query just returns no samples. To avoid leaving the source stuck on
    /// speed sync for a denying user, success here is defined as "actually retrieved a usable
    /// sample". A user who genuinely granted access but has no recent cycling-speed samples
    /// (e.g. no Apple Watch) is also routed to `.manual` — that's intentional.
    ///
    /// A sync invalidated by `stopSyncing()` (the user opted out while it was in
    /// flight) abandons without touching the store, so the opt-out wins.
    @discardableResult
    func requestAuthorizationAndSync() async -> Bool {
        guard let provider, provider.isAvailable else {
            userDataStore.bikeSpeedSource = .manual
            return false
        }

        let generation = syncGeneration

        do {
            try await provider.requestAuthorization()
        } catch {
            Logger.error("BikeModeManager: provider requestAuthorization failed: \(error)")
            guard generation == syncGeneration else { return false }
            userDataStore.bikeSpeedSource = .manual
            return false
        }

        guard generation == syncGeneration else { return false }

        let didSync = await syncAverageBikeSpeed(from: provider, expectedGeneration: generation)
        if !didSync, generation == syncGeneration {
            userDataStore.bikeSpeedSource = .manual
        }
        return didSync
    }

    /// Passive refresh used at launch when the user already opted into speed sync.
    /// Updates `bikeSpeedMetersPerSecond` if a fresh sample is available, but never flips
    /// `bikeSpeedSource` to `.manual` — an idle user keeps their previously-synced value and
    /// their stated intent. Only the active sync path in Settings can downgrade the source.
    func refreshIfPossible() async {
        guard let provider, provider.isAvailable else { return }
        let generation = syncGeneration
        await syncAverageBikeSpeed(from: provider, expectedGeneration: generation)
    }

    /// Fetches the average cycling speed and writes it to the store if it's in `BikeSpeed.validRange`.
    /// Returns `true` on a successful write; otherwise leaves the stored speed and source untouched
    /// and returns `false`. Callers decide how to react to a `false` result.
    /// When `expectedGeneration` no longer matches (opt-out raced the sync), the write is
    /// abandoned and `false` is returned without touching the store.
    @discardableResult
    private func syncAverageBikeSpeed(from provider: any SpeedProviding, expectedGeneration: Int? = nil) async -> Bool {
        guard let mps = await provider.fetchSpeed(),
              BikeSpeed.validRange.contains(mps)
        else {
            return false
        }

        if let expectedGeneration, expectedGeneration != syncGeneration {
            return false
        }

        userDataStore.bikeSpeedMetersPerSecond = mps
        userDataStore.bikeSpeedSource = .synced
        return true
    }
}
