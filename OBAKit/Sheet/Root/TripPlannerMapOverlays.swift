//
//  TripPlannerMapOverlays.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import MapKit

/// Trip planner map content: the planned route polylines and the trip's annotations
/// (start, end, intermediate stops).
///
/// A free function rather than inline map content because `MapPanelRootView.body`
/// has already exceeded Swift's type-check budget once.
///
/// The routes and annotations are insertion-ordered on purpose: OTPKit draws a white
/// halo under each leg and then the coloured line on top, so the order it adds them
/// in *is* the z-order. Annotations (drawn last) sit on top of all routes.
@MapContentBuilder
func tripPlannerMapContent(
    for display: TripPlannerMapDisplayModel
) -> some MapContent {
    // Draw routes in insertion order to preserve z-order (halos first, then
    // coloured lines on top).
    ForEach(display.routes) { route in
        MapPolyline(
            MKPolyline(coordinates: route.coordinates, count: route.coordinates.count)
        )
        .stroke(
            route.color,
            style: StrokeStyle(
                lineWidth: route.lineWidth,
                lineCap: .round,
                lineJoin: .round,
                dash: (route.dashPattern ?? []).map { CGFloat($0.doubleValue) }
            )
        )
    }

    // Tagged with OTPKit's own opaque identifier so a tap routes back to OTPKit
    // verbatim — the panel never interprets it. Same tagging shape the ambient
    // stop and rental layers use, so all three share one `selection` binding.
    ForEach(display.annotations) { annotation in
        Annotation("", coordinate: annotation.coordinate) {
            tripAnnotationContent(for: annotation)
        }
        .tag(MapPinSelection.tripPlannerAnnotation(annotation.identifier))
    }
}

/// Builds the visual representation of a trip annotation pin.
@ViewBuilder
private func tripAnnotationContent(
    for annotation: TripPlannerMapDisplayModel.Annotation
) -> some View {
    VStack(spacing: 0) {
        // Route badge (if this annotation has transit route info).
        if let routeName = annotation.routeName,
           let backgroundColor = annotation.routeBackgroundColor,
           let textColor = annotation.routeTextColor {
            Text(routeName)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .foregroundColor(Color(textColor))
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
                .background(Color(backgroundColor))
                .cornerRadius(3)
                .padding(.bottom, 4)
        }

        // Primary title.
        Text(annotation.title)
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .foregroundColor(Color(uiColor: .label))

        // Optional subtitle.
        if let subtitle = annotation.subtitle {
            Text(subtitle)
                .font(.system(size: 10))
                .lineLimit(1)
                .foregroundColor(Color(uiColor: .secondaryLabel))
        }
    }
    .padding(6)
    .background(Color(uiColor: .systemBackground))
    .cornerRadius(6)
    .shadow(radius: 2)
}
