//
//  MapStatusIndicator.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// The single source of truth for what a map-status pill renders: an SF Symbol
/// name and a localized label. Both the UIKit `MapStatusView` and the SwiftUI
/// `MapStatusPill` map their own state enums onto this so the SF Symbol names
/// and `OBALoc` copy live in exactly one place and the two surfaces can't drift.
///
/// MapKit-free by design (symbol names are plain strings) so it stays usable
/// from either host without pulling MapKit into the presentation layer.
enum MapStatusIndicator {
    /// Location authorization is unavailable (not determined, denied, or
    /// system-restricted). Shown when the app can't use the user's location.
    case locationUnavailable

    /// Location is authorized but limited to reduced (approximate) accuracy.
    case preciseLocationUnavailable

    /// The map is zoomed out too far to load stops.
    case zoomInForStops

    /// SF Symbol used in the compact (SwiftUI pill / UIKit inline) presentation.
    var symbolName: String {
        switch self {
        case .locationUnavailable: return "location.slash"
        case .preciseLocationUnavailable: return "location.circle"
        case .zoomInForStops: return "plus.magnifyingglass"
        }
    }

    /// SF Symbol used for UIKit's large-content (accessibility zoom) image.
    /// Prefers the filled variant where one exists, matching the previous
    /// hand-rolled `MapStatusView` mapping.
    var largeSymbolName: String {
        switch self {
        case .locationUnavailable: return "location.slash.fill"
        case .preciseLocationUnavailable: return "location.circle.fill"
        case .zoomInForStops: return "plus.magnifyingglass"
        }
    }

    /// Localized label copy for the indicator.
    var localizedText: String {
        switch self {
        case .locationUnavailable:
            return OBALoc(
                "map_status_view.location_services_unavailable",
                value: "Location services unavailable",
                comment: "Displayed in the map status view at the top of the map when the user has declined to give the app access to their location"
            )
        case .preciseLocationUnavailable:
            return OBALoc(
                "map_status_view.precise_location_unavailable",
                value: "Precise location unavailable",
                comment: "Displayed in the map status view at the top of the map when the user has declined to give the app access to their precise location"
            )
        case .zoomInForStops:
            return OBALoc(
                "map_status_view.zoom_in_for_stops",
                value: "Zoom in for stops",
                comment: "Displayed in the map status view at the top of the map when the user must zoom in to see stops on the map"
            )
        }
    }
}
