//
//  OnDemandZoomLevel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Spec 2.2: the three zoom levels, decided from the visible map height in
/// map points alone. Published as a value so the layer, the dock and tests all
/// read one answer.
enum OnDemandZoomLevel: Equatable {
    /// Zoomed out past the zones' window: nothing draws.
    case hidden
    /// Filled polygons and one pin per service.
    case region
    /// Stroke-only polygons with a halo; the docked bar carries the status.
    case street

    /// The stop gate: at or under it the map is street level.
    static let streetMaxVisibleHeight: Double = MapRegionManager.requiredHeightToShowStops

    /// The zones layer's zoom window (15 times the stop gate).
    static let regionMaxVisibleHeight: Double = 600_000

    static func level(forVisibleHeight height: Double) -> OnDemandZoomLevel {
        if height <= streetMaxVisibleHeight { return .street }
        if height <= regionMaxVisibleHeight { return .region }
        return .hidden
    }
}
