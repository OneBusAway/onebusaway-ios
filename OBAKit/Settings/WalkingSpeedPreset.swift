//
//  WalkingSpeedPreset.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// User-selectable walking-speed presets, in meters per second.
/// Owns the raw speed value, the localized label, and the snap-to-nearest logic in one place.
enum WalkingSpeedPreset: Double, CaseIterable {
    case slow = 0.9
    case average = 1.4
    case fast = 1.8

    var localizedTitle: String {
        switch self {
        case .slow:
            return OBALoc("settings_controller.walking_speed.slow", value: "Slow (~2 mph)", comment: "Settings > Walking Speed > Slow preset label")
        case .average:
            return OBALoc("settings_controller.walking_speed.avg", value: "Average (~3 mph)", comment: "Settings > Walking Speed > Average preset label")
        case .fast:
            return OBALoc("settings_controller.walking_speed.fast", value: "Fast (~4 mph)", comment: "Settings > Walking Speed > Fast preset label")
        }
    }

    static func nearest(to speed: Double) -> WalkingSpeedPreset {
        allCases.min(by: { abs($0.rawValue - speed) < abs($1.rawValue - speed) }) ?? .average
    }
}

/// Pure computation of the next `(source, speed)` pair given the persisted state and the
/// values pulled out of the settings form. Extracted so the branching can be unit-tested
/// without instantiating a `FormViewController`.
struct WalkingSpeedSettingsDecision: Equatable {
    let source: WalkingSpeedSource
    let speed: Double

    /// - Parameters:
    ///   - currentSource: persisted source before this save.
    ///   - currentSpeed: persisted speed (m/s) before this save.
    ///   - useHealthKit: the HK toggle's form value, or `nil` if the row isn't present.
    ///   - segmentSpeed: the segmented-row speed (m/s), or `nil` if absent.
    static func compute(
        currentSource: WalkingSpeedSource,
        currentSpeed: Double,
        useHealthKit: Bool?,
        segmentSpeed: Double?
    ) -> WalkingSpeedSettingsDecision {
        // Source first so the manual-only speed write below sees the new source.
        let newSource: WalkingSpeedSource = useHealthKit.map { $0 ? .healthKit : .manual } ?? currentSource

        var newSpeed = currentSpeed
        if let segmentSpeed, newSource == .manual {
            newSpeed = segmentSpeed
        }
        // Snap to nearest preset when toggling HealthKit OFF so the segmented row matches.
        if useHealthKit == false {
            newSpeed = WalkingSpeedPreset.nearest(to: newSpeed).rawValue
        }

        return .init(source: newSource, speed: newSpeed)
    }
}
