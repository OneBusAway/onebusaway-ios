//
//  BikeSpeedHealthKitProviding.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import HealthKit
import OBAKitCore

/// Narrow seam around the two HealthKit operations `BikeModeManager` needs.
/// Exists so the manager's denial/sync state machine can be tested without a live `HKHealthStore`.
protocol BikeSpeedHealthKitProviding {
    /// `true` when HealthKit is usable on this device and the cycling-speed quantity type is available.
    var isAvailable: Bool { get }

    /// Requests read authorization for cycling-speed samples.
    /// May complete successfully even when the user denies — denial is detected by the absence of samples.
    func requestAuthorization() async throws

    /// Returns the most recent cycling-speed sample (m/s) from the last 30 days, or `nil` if none exists or the query fails.
    /// Does not apply range validation; the caller decides what counts as a usable sample.
    func fetchLatestBikeSpeed() async -> Double?
}

struct HKHealthStoreBikeSpeedProvider: BikeSpeedHealthKitProviding {
    private let healthStore = HKHealthStore()

    private static var cyclingSpeedType: HKQuantityType? {
        HKQuantityType.quantityType(forIdentifier: .cyclingSpeed)
    }

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable() && Self.cyclingSpeedType != nil
    }

    func requestAuthorization() async throws {
        guard let type = Self.cyclingSpeedType else { return }
        try await healthStore.requestAuthorization(toShare: [], read: [type])
    }

    func fetchLatestBikeSpeed() async -> Double? {
        guard let type = Self.cyclingSpeedType else { return nil }

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
                    Logger.error("BikeModeManager: HealthKit sample query failed: \(error)")
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
