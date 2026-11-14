//
//  FeatureFlags.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// UserDefaults keys for experimental, opt-in features, written by
/// Settings > Experimental.
public enum FeatureFlags {
    /// Gates the SwiftUI map panel experience (full-screen map + floating
    /// sheet) over the classic UIKit tab bar. Enabled by default; the
    /// Settings > Experimental toggle writes an explicit value, so turning it
    /// off opts back into the classic UI, and rebuilds the root at once.
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

    /// Gates on-device estimation of where a followed trip's vehicle is now, moving
    /// its marker between real-time updates (`VehicleTrack`). Off by default until
    /// the replay evaluation says otherwise. Read live; no relaunch needed.
    public static let estimatesVehiclePositionsKey = "OBAEstimatesVehiclePositions"

    /// Debug: draws the reported fix and the server's `position` beside an estimated
    /// vehicle marker, to compare them in the field.
    public static let showsRawVehicleFixKey = "OBAShowsRawVehicleFix"

    public static func isVehicleEstimationEnabled(userDefaults: UserDefaults) -> Bool {
        userDefaults.bool(forKey: estimatesVehiclePositionsKey)
    }

    /// For requests that carry vehicle positions: an estimate measured from a
    /// cached status would think its fix fresher than it is, and maglev marks these
    /// endpoints `max-age=30`. Unchanged while estimation is off.
    public static func realtimeCachePolicy(userDefaults: UserDefaults) -> URLRequest.CachePolicy {
        isVehicleEstimationEnabled(userDefaults: userDefaults) ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
    }

    public static func showsRawVehicleFix(userDefaults: UserDefaults) -> Bool {
        userDefaults.bool(forKey: showsRawVehicleFixKey)
    }
}
