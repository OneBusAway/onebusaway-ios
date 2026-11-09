//
//  WalkingSpeedManager.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// Resolves the user's walking speed from the app's speed provider (if it has one and is authorized) or falls back to a user preference.
@MainActor
final class WalkingSpeedManager {
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
    /// Back on manual, the speed is the preset nearest the stored speed.
    func stopSyncing() {
        syncGeneration += 1
        userDataStore.walkingSpeedSource = .manual
        userDataStore.walkingSpeedMetersPerSecond = WalkingSpeedPreset.nearest(to: userDataStore.walkingSpeedMetersPerSecond).rawValue
    }

    /// Requests the provider's authorization and attempts to sync the latest walking speed.
    ///
    /// The provider's privacy model does not surface read-permission denials: the
    /// authorization request succeeds even when the user taps "Don't Allow", and a
    /// subsequent query just returns no samples. To avoid leaving the toggle stuck ON
    /// for a denying user, success here is defined as "actually retrieved a usable
    /// sample". A user who genuinely granted access but has no recent walking-speed
    /// samples (e.g. no Apple Watch) is also routed to `.manual` — that's intentional.
    /// A sync invalidated by `stopSyncing()` (the user opted out while it was in
    /// flight) abandons without touching the store, so the opt-out wins.
    @discardableResult
    func requestAuthorizationAndSync() async -> Bool {
        guard let provider, provider.isAvailable else {
            userDataStore.walkingSpeedSource = .manual
            return false
        }

        let generation = syncGeneration

        do {
            try await provider.requestAuthorization()
        } catch {
            Logger.error("WalkingSpeedManager: provider requestAuthorization failed: \(error)")
            guard generation == syncGeneration else { return false }
            userDataStore.walkingSpeedSource = .manual
            return false
        }

        guard generation == syncGeneration else { return false }

        let didSync = await syncLatestWalkingSpeed(from: provider, expectedGeneration: generation)
        if !didSync, generation == syncGeneration {
            userDataStore.walkingSpeedSource = .manual
        }
        return didSync
    }

    /// Passive refresh used at launch when the user already opted into speed sync.
    /// Updates `walkingSpeedMetersPerSecond` if a fresh sample is available, but never
    /// flips `walkingSpeedSource` to `.manual` — an idle user (e.g. left their Apple Watch
    /// at home for a month) keeps their previously-synced value and their stated intent.
    /// Only the active toggle-on path in Settings can downgrade the source.
    func refreshIfPossible() async {
        guard let provider, provider.isAvailable else { return }
        let generation = syncGeneration
        await syncLatestWalkingSpeed(from: provider, expectedGeneration: generation)
    }

    /// Fetches the latest walking-speed sample and writes it to the store if it's in `WalkingSpeed.validRange`.
    /// Returns `true` on a successful write; otherwise leaves the stored speed and source untouched
    /// and returns `false`. Callers decide how to react to a `false` result.
    /// When `expectedGeneration` no longer matches (opt-out raced the sync), the write is
    /// abandoned and `false` is returned without touching the store.
    @discardableResult
    private func syncLatestWalkingSpeed(from provider: any SpeedProviding, expectedGeneration: Int? = nil) async -> Bool {
        guard let mps = await provider.fetchSpeed(),
              WalkingSpeed.validRange.contains(mps)
        else {
            return false
        }

        if let expectedGeneration, expectedGeneration != syncGeneration {
            return false
        }

        userDataStore.walkingSpeedMetersPerSecond = mps
        userDataStore.walkingSpeedSource = .synced
        return true
    }
}
