//
//  MapDisplaySettings.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// The Settings screen's Show Scale, Show Traffic and Show Heading switches.
///
/// Both maps read them: `MapRegionManager` applies them to its `MKMapView`,
/// and the map panel reads the same keys through `@AppStorage`. Each default
/// is written here once, so the two maps can't disagree on a fresh install.
struct MapDisplaySettings {

    // MARK: - Keys

    // These strings predate this type and hold riders' choices; never rename them.
    static let showsScaleKey = "mapRegionManager.mapViewShowsScale"
    static let showsTrafficKey = "mapRegionManager.mapViewShowsTraffic"
    static let showsHeadingKey = "mapRegionManager.mapViewShowsHeadingKey"

    // MARK: - Defaults

    static let defaultShowsScale = true
    static let defaultShowsTraffic = true
    static let defaultShowsHeading = true

    // MARK: - Values

    let userDefaults: UserDefaults

    /// Whether the map shows a scale while zooming.
    var showsScale: Bool {
        get { bool(forKey: Self.showsScaleKey, default: Self.defaultShowsScale) }
        nonmutating set { userDefaults.set(newValue, forKey: Self.showsScaleKey) }
    }

    /// The rider's Show Traffic choice. Maps draw ``effectiveShowsTraffic(_:)`` of it.
    var showsTraffic: Bool {
        get { bool(forKey: Self.showsTrafficKey, default: Self.defaultShowsTraffic) }
        nonmutating set { userDefaults.set(newValue, forKey: Self.showsTrafficKey) }
    }

    /// Whether the user location shows the direction the rider is facing.
    var showsHeading: Bool {
        get { bool(forKey: Self.showsHeadingKey, default: Self.defaultShowsHeading) }
        nonmutating set { userDefaults.set(newValue, forKey: Self.showsHeadingKey) }
    }

    private func bool(forKey key: String, default defaultValue: Bool) -> Bool {
        userDefaults.object(forKey: key) == nil ? defaultValue : userDefaults.bool(forKey: key)
    }

    /// The Show Traffic setting, except in the Simulator, where traffic is off
    /// to work around a bug in Xcode 11 and 12 where the console spews hundreds
    /// of "Compiler error: Invalid library file" messages.
    /// https://stackoverflow.com/a/63176707
    static func effectiveShowsTraffic(_ setting: Bool) -> Bool {
        #if targetEnvironment(simulator)
        false
        #else
        setting
        #endif
    }
}
