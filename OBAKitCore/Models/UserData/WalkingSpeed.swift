//
//  WalkingSpeed.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

// Raw values are persisted to UserDefaults — do not reorder or renumber existing cases.
@objc public enum WalkingSpeedSource: Int {
    case manual = 0    // user picked a preset
    case healthKit = 1 // synced from HealthKit
}

/// Shared constants for walking speed handling.
public enum WalkingSpeed {
    /// Average human walking speed (≈3.1 mph).
    public static let defaultMetersPerSecond: Double = 1.4

    /// Acceptable range for a stored walking speed, in meters per second.
    /// Values outside this range are treated as invalid (divide-hostile or implausible).
    public static let validRange: ClosedRange<Double> = 0.5...5.0
}
