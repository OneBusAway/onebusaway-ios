//
//  WalkingSpeedHealthKitProviding.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import HealthKit
import OBAKitCore

/// Narrow seam around the two HealthKit operations `WalkingSpeedManager` needs.
/// Exists so the manager's denial/sync state machine can be tested without a live `HKHealthStore`.
protocol WalkingSpeedHealthKitProviding {
    /// `true` when HealthKit is usable on this device and the walking-speed quantity type is available.
    var isAvailable: Bool { get }

    /// Requests read authorization for walking-speed samples.
    /// May complete successfully even when the user denies — denial is detected by the absence of samples.
    func requestAuthorization() async throws

    /// Returns the most recent walking-speed sample (m/s) from the last 30 days, or `nil` if none exists or the query fails.
    /// Does not apply range validation; the caller decides what counts as a usable sample.
    func fetchLatestWalkingSpeed() async -> Double?
}

struct HKHealthStoreWalkingSpeedProvider: WalkingSpeedHealthKitProviding {
    private let healthStore = HKHealthStore()

    private static var walkingSpeedType: HKQuantityType? {
        HKQuantityType.quantityType(forIdentifier: .walkingSpeed)
    }

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable() && Self.walkingSpeedType != nil
    }

    func requestAuthorization() async throws {
        guard let type = Self.walkingSpeedType else { return }
        try await healthStore.requestAuthorization(toShare: [], read: [type])
    }

    func fetchLatestWalkingSpeed() async -> Double? {
        guard let type = Self.walkingSpeedType else { return nil }

        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        let predicate = HKQuery.predicateForSamples(withStart: thirtyDaysAgo, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
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
                continuation.resume(returning: mps)
            }
            healthStore.execute(query)
        }
    }
}
