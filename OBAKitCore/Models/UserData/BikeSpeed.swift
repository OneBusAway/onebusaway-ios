//
//  BikeSpeed.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

// Raw values are persisted to UserDefaults — do not reorder or renumber existing cases.
@objc public enum BikeSpeedSource: Int {
    case manual = 0    // fixed fallback constant in effect
    case healthKit = 1 // synced from HealthKit
}

/// Shared constants for bike mode speed handling.
public enum BikeSpeed {
    /// Fallback cycling speed when HealthKit is unavailable, denied, or has no samples (≈15 km/h).
    public static let defaultMetersPerSecond: Double = 4.2

    /// Acceptable range for a stored bike speed, in meters per second (≈3.6–72 km/h).
    /// Values outside this range are treated as invalid (divide-hostile or implausible).
    public static let validRange: ClosedRange<Double> = 1.0...20.0
}
