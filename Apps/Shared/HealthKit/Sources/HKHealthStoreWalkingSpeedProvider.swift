//
//  HKHealthStoreWalkingSpeedProvider.swift
//  OneBusAway
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import HealthKit
import OBAKit
import OBAKitCore

struct HKHealthStoreWalkingSpeedProvider: SpeedProviding {
    let healthStore: HKHealthStore

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

    /// The most recent sample.
    func fetchSpeed() async -> Double? {
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
