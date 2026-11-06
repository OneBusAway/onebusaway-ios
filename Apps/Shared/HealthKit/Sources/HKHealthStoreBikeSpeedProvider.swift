//
//  HKHealthStoreBikeSpeedProvider.swift
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

struct HKHealthStoreBikeSpeedProvider: SpeedProviding {
    let healthStore: HKHealthStore

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

    /// An average, because the single newest reading is often taken as the rider slows to a stop.
    func fetchSpeed() async -> Double? {
        guard let type = Self.cyclingSpeedType else { return nil }

        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        let predicate = HKQuery.predicateForSamples(withStart: thirtyDaysAgo, end: Date())

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, error in
                if let error {
                    Logger.error("BikeModeManager: HealthKit average query failed: \(error)")
                    continuation.resume(returning: nil)
                    return
                }
                guard let average = statistics?.averageQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                let mps = average.doubleValue(for: HKUnit.meter().unitDivided(by: .second()))
                continuation.resume(returning: mps)
            }
            healthStore.execute(query)
        }
    }
}
