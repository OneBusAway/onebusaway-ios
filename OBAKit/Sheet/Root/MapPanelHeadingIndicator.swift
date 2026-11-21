//
//  MapPanelHeadingIndicator.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Observation
import OBAKitCore
import SwiftUI

/// Which puck ``MapPanelUserLocation`` draws, and where its heading cone
/// points. Kept apart from the view so tests can check it without a `Map`.
enum MapPanelHeadingIndicator {

    /// Under reduced accuracy MapKit's puck draws the imprecise area, which the
    /// panel's dot can't — the same reason the UIKit map keeps
    /// `MKUserLocationView` then. With Show Heading off the panel keeps its dot,
    /// since MapKit's puck has no switch to hide its cone.
    static func usesSystemPuck(showsHeading: Bool, isReducedAccuracy: Bool) -> Bool {
        showsHeading && isReducedAccuracy
    }

    /// How far to turn the cone, or `nil` for no cone: Show Heading is off, or
    /// there's no heading to show (no magnetometer, or no reading yet).
    static func coneRotation(
        showsHeading: Bool,
        direction: CLLocationDirection?,
        cameraHeading: CLLocationDirection
    ) -> Angle? {
        guard showsHeading, let direction else { return nil }
        return coneRotation(direction: direction, cameraHeading: cameraHeading)
    }

    /// The compass direction the rider faces, or `nil` when `heading` has none.
    ///
    /// A negative `headingAccuracy` means the reading is invalid. True heading
    /// needs a location fix and reads negative until one arrives; magnetic
    /// heading is a few degrees off, but better than no cone.
    static func direction(of heading: CLHeading?) -> CLLocationDirection? {
        guard let heading, heading.headingAccuracy >= 0 else { return nil }
        return heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
    }

    /// Annotations stay upright as the map turns, so the cone takes off the
    /// camera's heading. The `heading` asset points east, hence the quarter
    /// turn, as in `PulsingAnnotationView.showUserHeading(_:)`.
    static func coneRotation(direction: CLLocationDirection, cameraHeading: CLLocationDirection) -> Angle {
        let degrees = (direction - cameraHeading - 90).truncatingRemainder(dividingBy: 360)
        return .degrees(degrees < 0 ? degrees + 360 : degrees)
    }
}

/// `LocationService` reports heading through its delegates; this republishes
/// it to SwiftUI. Observable, so only the views that read ``direction`` redraw
/// as the rider turns, not the whole map panel.
@Observable
final class MapPanelHeadingObserver: NSObject, LocationServiceDelegate {
    private(set) var direction: CLLocationDirection?
    private(set) var isReducedAccuracy: Bool

    init(locationService: LocationService) {
        direction = MapPanelHeadingIndicator.direction(of: locationService.currentHeading)
        isReducedAccuracy = locationService.accuracyAuthorization == .reducedAccuracy
        super.init()
        // The delegate table is weak, so this doesn't keep the observer alive.
        locationService.addDelegate(self)
    }

    func locationService(_ service: LocationService, headingChanged heading: CLHeading?) {
        direction = MapPanelHeadingIndicator.direction(of: heading)
    }

    func locationService(_ service: LocationService, accuracyAuthorizationChanged accuracyAuthorization: CLAccuracyAuthorization) {
        isReducedAccuracy = accuracyAuthorization == .reducedAccuracy
    }
}
