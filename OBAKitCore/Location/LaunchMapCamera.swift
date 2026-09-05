//
//  LaunchMapCamera.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import MapKit

/// Launch (and first-fix) camera for the map. GPS inside the selected region
/// still zooms to the user so nearby stops appear. GPS outside must not win
/// over the region the rider picked (#615). The locate button is a separate
/// path and always centers on the user.
public enum LaunchMapCamera {

    public enum Target {
        /// Device is inside the selected region's service rect.
        case userLocation
        /// Last in-region viewport, or the region's service rect.
        case mapRect(MKMapRect, showRegionMismatch: Bool)
    }

    public static func target(
        selectedRegion: Region,
        userLocation: CLLocation?,
        lastVisibleMapRect: MKMapRect?
    ) -> Target {
        if let userLocation, selectedRegion.contains(location: userLocation) {
            return .userLocation
        }

        let showMismatch = userLocation != nil
        let rect: MKMapRect
        if let lastVisibleMapRect {
            if showMismatch {
                rect = lastVisibleMapRect.intersects(selectedRegion.serviceRect)
                    ? lastVisibleMapRect
                    : selectedRegion.serviceRect
            } else {
                rect = lastVisibleMapRect
            }
        } else {
            rect = selectedRegion.serviceRect
        }
        return .mapRect(rect, showRegionMismatch: showMismatch)
    }
}
