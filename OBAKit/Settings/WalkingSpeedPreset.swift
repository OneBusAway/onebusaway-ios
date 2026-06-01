//
//  WalkingSpeedPreset.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

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
