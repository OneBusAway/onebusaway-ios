//
//  FeatureFlags.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// UserDefaults keys for experimental, opt-in features. Read at app
/// construction; changes generally require a relaunch to take effect.
public enum FeatureFlags {
    /// Gates the SwiftUI map panel experience (full-screen map + floating
    /// sheet) over the classic UIKit tab bar. Enabled by default; the
    /// Settings > Experimental toggle writes an explicit value, so turning it
    /// off opts back into the classic UI.
    public static let useMapPanelExperienceKey = "OBAUseMapPanelExperience"

    /// Gates MapKit clustering of stop pins (#515). Off by default while the
    /// feature is refined (#1600).
    public static let clustersStopsKey = "OBAClustersStops"

    /// Resolves the map panel flag, defaulting to enabled when the user has
    /// never touched the toggle. A set value goes through `bool(forKey:)`, so
    /// a launch argument's `NO` (a string) opts out as the toggle's `false` does.
    public static func isMapPanelExperienceEnabled(userDefaults: UserDefaults) -> Bool {
        guard userDefaults.object(forKey: useMapPanelExperienceKey) != nil else { return true }
        return userDefaults.bool(forKey: useMapPanelExperienceKey)
    }
}
