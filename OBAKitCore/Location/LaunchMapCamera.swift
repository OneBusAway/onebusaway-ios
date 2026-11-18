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

    public enum Target: Equatable, Sendable {
        /// Device is inside the selected region's service rect.
        case userLocation
        /// Last in-region viewport, or the region's service rect.
        case mapRect(MKMapRect, showRegionMismatch: Bool)

        public static func == (lhs: Target, rhs: Target) -> Bool {
            switch (lhs, rhs) {
            case (.userLocation, .userLocation):
                return true
            case let (.mapRect(lhsRect, lhsMismatch), .mapRect(rhsRect, rhsMismatch)):
                return MKMapRectEqualToRect(lhsRect, rhsRect) && lhsMismatch == rhsMismatch
            default:
                return false
            }
        }
    }

    // MARK: - Validation Helpers

    /// Validates camera coordinates: latitude in -90...90, longitude in -180...180, and finite.
    public static func isValidCoordinate(_ coordinate: CLLocationCoordinate2D) -> Bool {
        guard coordinate.latitude.isFinite,
              coordinate.longitude.isFinite,
              CLLocationCoordinate2DIsValid(coordinate)
        else {
            return false
        }
        return true
    }

    /// Validates a location's coordinate.
    public static func isValidLocation(_ location: CLLocation?) -> Bool {
        guard let location else { return false }
        return isValidCoordinate(location.coordinate)
    }

    /// Validates zoom/rect dimensions: finite, width > 0, height > 0, not null/empty/infinite.
    /// Does not require containment in `MKMapRect.world` so viewports spanning the 180th meridian
    /// or zoomed-out viewports running past world edges remain valid.
    public static func isValidMapRect(_ rect: MKMapRect) -> Bool {
        guard !rect.isNull,
              !rect.isEmpty,
              rect.origin.x.isFinite,
              rect.origin.y.isFinite,
              rect.size.width.isFinite,
              rect.size.height.isFinite,
              rect.size.width > 0,
              rect.size.height > 0
        else {
            return false
        }
        return true
    }

    /// Validates that a region exists and its serviceRect is valid.
    public static func isValidRegion(_ region: Region?) -> Bool {
        guard let region else { return false }
        return isValidMapRect(region.serviceRect)
    }

    /// Returns the region's service rect if valid; falls back safely to `MKMapRect.world` if malformed.
    public static func safeServiceRect(for region: Region?) -> MKMapRect {
        guard let region, isValidMapRect(region.serviceRect) else {
            return MKMapRect.world
        }
        return region.serviceRect
    }

    // MARK: - Target Calculation

    /// Evaluates the launch camera target for the given region, user location, and last visible map rect.
    ///
    /// Fails safely on malformed input (e.g. discards invalid/out-of-range/NaN `userLocation` instead
    /// of zooming to it; discards invalid/null/empty/infinite/NaN `lastVisibleMapRect` in favor of region `serviceRect`).
    public static func target(
        selectedRegion: Region,
        userLocation: CLLocation? = nil,
        lastVisibleMapRect: MKMapRect? = nil
    ) -> Target {
        let validUserLocation: CLLocation? = isValidLocation(userLocation) ? userLocation : nil
        let validLastVisibleMapRect: MKMapRect?
        if let lastVisibleMapRect, isValidMapRect(lastVisibleMapRect) {
            validLastVisibleMapRect = lastVisibleMapRect
        } else {
            validLastVisibleMapRect = nil
        }

        let fallbackRect = safeServiceRect(for: selectedRegion)

        if let validUserLocation, isValidMapRect(selectedRegion.serviceRect), selectedRegion.contains(location: validUserLocation) {
            return .userLocation
        }

        let showMismatch = validUserLocation != nil
        let rect: MKMapRect
        if let validLast = validLastVisibleMapRect {
            if showMismatch {
                rect = validLast.intersects(fallbackRect)
                    ? validLast
                    : fallbackRect
            } else {
                rect = validLast
            }
        } else {
            rect = fallbackRect
        }
        return .mapRect(rect, showRegionMismatch: showMismatch)
    }

    /// Where the map goes when the rider changes region: to the rider when
    /// they're in it (nil), otherwise to its service rect. Unlike `target`, the
    /// last viewport is in the old region, so it is never used.
    ///
    /// Fails safely on malformed input: discards invalid/out-of-range/NaN `userLocation`.
    public static func regionChangeTarget(
        region: Region,
        userLocation: CLLocation? = nil
    ) -> MKMapRect? {
        let validUserLocation: CLLocation? = isValidLocation(userLocation) ? userLocation : nil
        if let validUserLocation, isValidMapRect(region.serviceRect), region.contains(location: validUserLocation) {
            return nil
        }
        return safeServiceRect(for: region)
    }
}
