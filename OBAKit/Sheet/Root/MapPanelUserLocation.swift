//
//  MapPanelUserLocation.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import SwiftUI

/// The rider's location on the map panel's `Map`, honoring Settings > Show Heading.
///
/// The panel draws its own dot and heading cone, as the UIKit map does with
/// `PulsingAnnotationView`: MapKit's puck draws its cone in system blue and
/// has no switch to hide it. Read through `@AppStorage`, so flipping the
/// switch in Settings redraws it.
struct MapPanelUserLocation: MapContent {
    @AppStorage private(set) var showsHeading: Bool

    private let headingObserver: MapPanelHeadingObserver
    private let isReducedAccuracy: Bool
    private let cameraHeading: CLLocationDirection

    /// `isReducedAccuracy` is passed in rather than read off `headingObserver`
    /// so the caller's view body, which Observation tracks, does the reading.
    init(
        userDefaults: UserDefaults,
        headingObserver: MapPanelHeadingObserver,
        isReducedAccuracy: Bool,
        cameraHeading: CLLocationDirection
    ) {
        _showsHeading = AppStorage(wrappedValue: MapDisplaySettings.defaultShowsHeading, MapDisplaySettings.showsHeadingKey, store: userDefaults)
        self.headingObserver = headingObserver
        self.isReducedAccuracy = isReducedAccuracy
        self.cameraHeading = cameraHeading
    }

    var body: some MapContent {
        if MapPanelHeadingIndicator.usesSystemPuck(showsHeading: showsHeading, isReducedAccuracy: isReducedAccuracy) {
            UserAnnotation()
        } else {
            UserAnnotation {
                MapPanelUserLocationDot(
                    showsHeading: showsHeading,
                    headingObserver: headingObserver,
                    cameraHeading: cameraHeading
                )
            }
        }
    }
}

/// A view of its own so that a heading update redraws only this, not the `Map`.
private struct MapPanelUserLocationDot: View {
    let showsHeading: Bool
    let headingObserver: MapPanelHeadingObserver
    let cameraHeading: CLLocationDirection

    var body: some View {
        ZStack {
            if let coneRotation = MapPanelHeadingIndicator.coneRotation(
                showsHeading: showsHeading,
                direction: headingObserver.direction,
                cameraHeading: cameraHeading
            ) {
                // Natural size, centered on the dot, as on the UIKit map.
                Image(uiImage: Icons.templateHeading)
                    .renderingMode(.template)
                    .foregroundStyle(.tint)
                    .rotationEffect(coneRotation)
                    // The cone is far bigger than the dot. On the UIKit map it
                    // hangs outside its view's bounds, so taps reach the stops
                    // under it; keep it that way here.
                    .allowsHitTesting(false)
                    // The dot already stands for the rider; the cone is decoration.
                    .accessibilityHidden(true)
            }
            Circle()
                // MapKit's puck takes the app's tint too.
                .fill(.tint)
                .frame(width: 18, height: 18)
                .overlay(Circle().stroke(Color.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.3), radius: 2)
        }
    }
}
