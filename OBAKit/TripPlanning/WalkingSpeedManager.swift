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
    /// Returns `true` if the authorization request completed without error.
    /// Returns `false` only if HealthKit is unavailable or the authorization request threw an error.
    @discardableResult
    func requestHealthKitAuthorizationAndSync() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable(),
              let speedType = HKQuantityType.quantityType(forIdentifier: .walkingSpeed)
        else { return false }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: [speedType])
        } catch {
            Logger.error("WalkingSpeedManager: HealthKit requestAuthorization failed: \(error)")
            userDataStore.walkingSpeedSource = .manual
            return false
        }

        await syncLatestWalkingSpeed(speedType: speedType)
        return true
    }

    /// Queries HealthKit for the most recent walking speed sample from the last 30 days.
    /// If a valid sample is found, writes it to UserDataStore.
    /// If no sample is found or it's out of range, does nothing (keeps current manual preset).
    @discardableResult
    private func syncLatestWalkingSpeed(speedType: HKQuantityType) async -> Bool {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: thirtyDaysAgo, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        // Snapshot the static range outside the closure to make the non-capture explicit.
        let validRange = 0.5...5.0

        let validSpeed: Double? = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: speedType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                // This callback runs on a background thread. No self captured here.
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
            return true
        }
        return false
    }
}
