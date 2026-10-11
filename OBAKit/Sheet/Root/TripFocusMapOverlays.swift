//
//  TripFocusMapOverlays.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import MapKit
import OBAKitCore

/// The open trip sheet's trip on the panel's map: its shape split at the vehicle,
/// direction arrows along the part still ahead, a dot for every stop, and the
/// vehicle. Drawn to match `TripFocusMapLayer` on the map tab, and sized from its
/// `Style`.
///
/// A free function rather than inline map content because `MapPanelRootView.body`
/// has already exceeded Swift's type-check budget once.
@MapContentBuilder
func tripFocusMapContent(for display: TripFocusMapDisplayModel.Display?) -> some MapContent {
    if let display {
        // Spent first, then ahead, so where the two meet the live half wins the
        // z-order. Casing before core within each, for the same reason.
        if let spent = display.spent {
            MapPolyline(spent.casing)
                .stroke(Color.white.opacity(TripFocusMapLayer.Style.spentAlpha), style: tripShapeStroke(
                    width: TripFocusMapLayer.Style.spentCoreWidth + TripFocusMapLayer.Style.casingExtraWidth
                ))
            MapPolyline(spent.core)
                .stroke(Color(uiColor: .systemGray3).opacity(TripFocusMapLayer.Style.spentAlpha), style: tripShapeStroke(
                    width: TripFocusMapLayer.Style.spentCoreWidth
                ))
        }
        if let ahead = display.ahead {
            MapPolyline(ahead.casing)
                .stroke(.white, style: tripShapeStroke(
                    width: TripFocusMapLayer.Style.coreWidth + TripFocusMapLayer.Style.casingExtraWidth
                ))
            MapPolyline(ahead.core)
                .stroke(display.routeColor, style: tripShapeStroke(width: TripFocusMapLayer.Style.coreWidth))
        }

        ForEach(Array(display.arrows.enumerated()), id: \.offset) { _, arrow in
            Annotation("", coordinate: arrow.coordinate, anchor: .center) {
                TripDirectionArrow(headingDegrees: arrow.headingDegrees, color: display.routeColor)
            }
        }

        ForEach(display.stops) { stop in
            Annotation("", coordinate: stop.coordinate, anchor: .center) {
                TripStopDot(stop: stop, routeColor: display.routeColor)
            }
        }

        if let vehicle = display.vehicle {
            Annotation("", coordinate: vehicle.coordinate, anchor: .center) {
                TripVehicleMarker(vehicle: vehicle, routeColor: display.routeColor)
            }
        }
    }
}

private func tripShapeStroke(width: CGFloat) -> StrokeStyle {
    StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
}

/// A chevron pointing the way the trip runs, as `PolylineArrowAnnotationView` draws
/// it on the map tab.
private struct TripDirectionArrow: View {
    let headingDegrees: CLLocationDirection
    let color: Color

    var body: some View {
        // `chevron.up` points north unrotated, and compass headings run clockwise,
        // as a positive rotation does here. See `PolylineDirectionArrows.viewTransform`.
        Image(systemName: "chevron.up")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(color)
            .rotationEffect(.degrees(headingDegrees))
            // Decorative, as on the map tab: dozens of unlabeled chevrons would
            // flood the VoiceOver rotor.
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

/// A stop on the open trip, sized and colored as `TripStopAnnotationView` draws it
/// on the map tab.
private struct TripStopDot: View {
    let stop: TripFocusMapDisplayModel.TripStop
    let routeColor: Color

    private var diameter: CGFloat {
        if stop.isUserStop { return TripFocusMapLayer.Style.userStopDiameter }
        if stop.isTerminal { return TripFocusMapLayer.Style.terminalStopDiameter }
        return TripFocusMapLayer.Style.stopDiameter
    }

    var body: some View {
        let stroke = stop.isPassed ? Color(uiColor: .systemGray3) : routeColor
        let fill = stop.isPassed ? Color(uiColor: .systemGray3) : Color(uiColor: .secondarySystemGroupedBackground)

        Circle()
            .fill(stop.isUserStop ? stroke : fill)
            .overlay(Circle().stroke(stroke, lineWidth: TripFocusMapLayer.Style.stopRingWidth))
            .frame(width: diameter, height: diameter)
            .accessibilityLabel(stop.name)
    }
}

/// The open trip's vehicle, laid out as `PulsingVehicleAnnotationView` draws it on
/// the map tab: a route-colored dot with the mode's icon, gray when the position is
/// scheduled rather than live, and a heading ring behind it when it's live.
private struct TripVehicleMarker: View {
    let vehicle: TripFocusMapDisplayModel.TripVehicle
    let routeColor: Color

    private static let diameter = TripFocusMapLayer.Style.vehicleDiameter

    var body: some View {
        let color = vehicle.isRealTime ? routeColor : Color(uiColor: ThemeColors.shared.gray)

        ZStack {
            if vehicle.isRealTime {
                // Negated because OBA's orientation turns the other way from a
                // screen rotation; see `PulsingVehicleAnnotationView.updateHeading`.
                Image(uiImage: Icons.templateHeading)
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: Self.diameter * 3, height: Self.diameter * 3)
                    .foregroundStyle(color)
                    .rotationEffect(.radians(-vehicle.orientation.radians))
            }
            Circle()
                .fill(color)
                .frame(width: Self.diameter, height: Self.diameter)
            Image(uiImage: Icons.transportIcon(from: vehicle.routeType))
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: Self.diameter / 2, height: Self.diameter / 2)
                .foregroundStyle(.white)
        }
        // The page's stop list already marks the stop the bus is at, and the map
        // tab's marker isn't interactive either.
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
