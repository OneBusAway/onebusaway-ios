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
/// MapKit's own puck draws the heading cone and has no switch to hide it, so
/// with Show Heading off the panel draws a plain dot in its place. Read
/// through `@AppStorage`, so flipping the switch in Settings redraws it.
struct MapPanelUserLocation: MapContent {
    @AppStorage private(set) var showsHeading: Bool

    init(userDefaults: UserDefaults) {
        _showsHeading = AppStorage(wrappedValue: MapDisplaySettings.defaultShowsHeading, MapDisplaySettings.showsHeadingKey, store: userDefaults)
    }

    var body: some MapContent {
        if showsHeading {
            UserAnnotation()
        } else {
            UserAnnotation {
                Circle()
                    // MapKit's puck takes the app's tint too.
                    .fill(.tint)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(Color.white, lineWidth: 3))
                    .shadow(color: .black.opacity(0.3), radius: 2)
            }
        }
    }
}
