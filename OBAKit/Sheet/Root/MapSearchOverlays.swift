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

/// Search-result map content: the route polyline and the searched place marker.
///
/// A free function rather than inline map content because `MapPanelRootView.body`
/// has already exceeded Swift's type-check budget once.
@MapContentBuilder
func searchResultMapContent(for display: MapSearchDisplayModel.Display) -> some MapContent {
    switch display {
    case .route(let route):
        ForEach(Array(route.polylines.enumerated()), id: \.offset) { _, polyline in
            MapPolyline(polyline)
                .stroke(route.color, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
    case .mapItem(let item):
        Marker(item.name ?? "", coordinate: item.placemark.coordinate)
    case .stop, .none:
        // Stops are already drawn by the ambient stop layer; nothing extra to add.
        EmptyMapContent()
    }
}
