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
    private let healthStore = HKHealthStore()
    private let userDataStore: UserDataStore

    init(userDataStore: UserDataStore) {
        self.userDataStore = userDataStore
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
        guard HKHealthStore.isHealthDataAvailable(),
              let speedType = HKQuantityType.quantityType(forIdentifier: .walkingSpeed)
        else {
            userDataStore.walkingSpeedSource = .manual
            return false
        }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: [speedType])
        } catch {
            Logger.error("WalkingSpeedManager: HealthKit requestAuthorization failed: \(error)")
            userDataStore.walkingSpeedSource = .manual
            return false
        }

        let didSync = await syncLatestWalkingSpeed(speedType: speedType)
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
        guard HKHealthStore.isHealthDataAvailable(),
              let speedType = HKQuantityType.quantityType(forIdentifier: .walkingSpeed)
        else { return }

        await syncLatestWalkingSpeed(speedType: speedType)
    }

    /// Queries HealthKit for the most recent walking speed sample from the last 30 days.
    /// If a valid sample is found, writes it to UserDataStore.
    /// If no sample is found or it's out of range, does nothing (keeps current manual preset).
    @discardableResult
    private func syncLatestWalkingSpeed(speedType: HKQuantityType) async -> Bool {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: thirtyDaysAgo, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let validRange = WalkingSpeed.validRange

        let validSpeed: Double? = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: speedType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    Logger.error("WalkingSpeedManager: HealthKit sample query failed: \(error)")
                    continuation.resume(returning: nil)
                    return
                }

                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }

                let mps = sample.quantity.doubleValue(for: HKUnit.meter().unitDivided(by: .second()))

                guard validRange.contains(mps) else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: mps)
            }
            healthStore.execute(query)
        }

        if let speed = validSpeed {
            userDataStore.walkingSpeedMetersPerSecond = speed
            userDataStore.walkingSpeedSource = .healthKit
            return true
        }
        return false
    }
}
