//
//  NearbyCoordinateResolver.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import OBAKitCore

/// Picks the coordinate the Nearby Stops index searches around.
///
/// `AppSheetRoute.nearbyAll` carries no payload — it's pushed from a section
/// header, not from a tapped place — so the anchor has to be resolved at build
/// time. Kept as a pure function rather than inlined into the factory so the
/// fallback chain is assertable without an `Application`.
nonisolated enum NearbyCoordinateResolver {

    /// Preference order: the map's last settled center, then the device's
    /// location, then the current region's center. Nil when none is available,
    /// which the view renders as an empty state rather than searching (0, 0).
    static func coordinate(
        viewportCenter: CLLocationCoordinate2D?,
        currentLocation: CLLocation?,
        region: Region?
    ) -> CLLocationCoordinate2D? {
        viewportCenter
            ?? currentLocation?.coordinate
            ?? region?.centerCoordinate
    }
}
