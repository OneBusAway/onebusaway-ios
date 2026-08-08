//
//  MapSearchOverlays.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import MapKit
import OBAKitCore

/// Search-result map content: the route polyline, the route's own stops, and the
/// searched place marker.
///
/// A free function rather than inline map content because `MapPanelRootView.body`
/// has already exceeded Swift's type-check budget once.
///
/// - Parameter stopIcon: Builds the pin image for a stop. Passed in rather than
///   resolved here because the icon depends on `Application.stopIconFactory` and the
///   current interface style, both of which live on the view.
@MapContentBuilder
func searchResultMapContent(
    for display: MapSearchDisplayModel.Display,
    stopIcon: @escaping (Stop) -> UIImage
) -> some MapContent {
    switch display {
    case .route(let route):
        ForEach(Array(route.polylines.enumerated()), id: \.offset) { _, polyline in
            MapPolyline(polyline)
                .stroke(route.color, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
        // A drawn route suppresses the ambient stop layer, so these are the only
        // stops on the map — matching the UIKit route search, which replaces the
        // visible annotations with the route's own. Tagged like ambient stops so
        // tapping one opens its details.
        ForEach(route.stops) { stop in
            Annotation("", coordinate: stop.coordinate) {
                Image(uiImage: stopIcon(stop))
                    .accessibilityLabel(Formatters.formattedAccessibilityLabel(stop: stop))
            }
            .tag(stop.id)
        }
    case .mapItem(let item):
        Marker(item.name ?? "", coordinate: item.placemark.coordinate)
    case .stop, .none:
        // Stops are already drawn by the ambient stop layer; nothing extra to add.
        EmptyMapContent()
    }
}
