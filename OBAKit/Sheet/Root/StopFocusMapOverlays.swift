//
//  StopFocusMapOverlays.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import MapKit
import OBAKitCore

/// The open stop sheet's routes on the panel's map, with direction arrows along
/// each, and the vehicles arriving on them. Drawn to match `StopRouteFocusMapLayer`
/// on the map tab, and sized from its `Style`.
///
/// A free function for the reason `tripFocusMapContent(for:)` is one:
/// `MapPanelRootView.body` has already exceeded Swift's type-check budget once.
@MapContentBuilder
func stopFocusMapContent(
    for display: StopFocusMapDisplayModel.Display?,
    onSelectVehicle: @escaping (StopFocusMapDisplayModel.Vehicle) -> Void
) -> some MapContent {
    if let display {
        // Dimmed routes first, so a focused route draws over the streets it shares.
        ForEach(display.routes.sorted { $0.emphasis.drawOrder < $1.emphasis.drawOrder }) { route in
            let opacity = route.emphasis.opacity
            let coreWidth = route.emphasis == .focused
                ? StopRouteFocusMapLayer.Style.focusedCoreWidth
                : StopRouteFocusMapLayer.Style.coreWidth
            MapPolyline(route.line.casing)
                .stroke(route.casingColor.opacity(opacity), style: tripShapeStroke(
                    width: coreWidth + RouteArrowStyle.casingExtraWidth
                ))
            MapPolyline(route.line.core)
                .stroke(route.color.opacity(opacity), style: tripShapeStroke(width: coreWidth))
        }

        ForEach(display.routes) { route in
            ForEach(Array(route.arrows.enumerated()), id: \.offset) { _, arrow in
                Annotation("", coordinate: arrow.coordinate, anchor: .center) {
                    TripDirectionArrow(headingDegrees: arrow.headingDegrees, color: route.arrowColor)
                        .opacity(route.emphasis.opacity)
                }
            }
        }

        ForEach(display.vehicles) { vehicle in
            Annotation("", coordinate: vehicle.coordinate, anchor: .center) {
                StopVehicleButton(vehicle: vehicle, onSelect: onSelectVehicle)
            }
        }
    }
}

private extension StopFocusMapDisplayModel.Emphasis {
    var opacity: Double {
        self == .dimmed ? StopRouteFocusMapLayer.Style.dimmedAlpha : StopRouteFocusMapLayer.Style.normalAlpha
    }

    var drawOrder: Int {
        switch self {
        case .dimmed: 0
        case .normal: 1
        case .focused: 2
        }
    }
}

/// An arriving vehicle. A tap opens its trip, where the panel follows that one
/// vehicle along its route.
private struct StopVehicleButton: View {
    let vehicle: StopFocusMapDisplayModel.Vehicle
    let onSelect: (StopFocusMapDisplayModel.Vehicle) -> Void

    var body: some View {
        Button {
            onSelect(vehicle)
        } label: {
            PanelVehicleMarker(
                routeType: vehicle.routeType,
                isRealTime: vehicle.isRealTime,
                orientation: vehicle.orientation,
                routeColor: vehicle.color,
                staleness: vehicle.staleness
            )
            .opacity(vehicle.emphasis.opacity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(vehicle.accessibilityLabel)
        .accessibilityValue(vehicle.accessibilityValue)
        .accessibilityHint(OBALoc(
            "map_panel.stop_vehicle.hint",
            value: "Shows this trip.",
            comment: "VoiceOver hint on a vehicle marker drawn for an open stop on the map panel. Tapping it opens the vehicle's trip."
        ))
    }
}
