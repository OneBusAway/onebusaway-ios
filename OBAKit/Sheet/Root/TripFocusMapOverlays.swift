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
func tripFocusMapContent(
    for display: TripFocusMapDisplayModel.Display?,
    vehicle: TripFocusMapDisplayModel.TripVehicle?,
    reportedPositions: [ReportedPosition] = []
) -> some MapContent {
    if let display {
        // Spent first, then ahead, so where the two meet the live half wins the
        // z-order. Casing before core within each, for the same reason.
        if let spent = display.spent {
            MapPolyline(spent.casing)
                .stroke(Color.white.opacity(TripFocusMapLayer.Style.spentAlpha), style: tripShapeStroke(
                    width: TripFocusMapLayer.Style.spentCoreWidth + TripFocusMapLayer.Style.spentCasingExtraWidth
                ))
            MapPolyline(spent.core)
                .stroke(Color(uiColor: .systemGray3).opacity(TripFocusMapLayer.Style.spentAlpha), style: tripShapeStroke(
                    width: TripFocusMapLayer.Style.spentCoreWidth
                ))
        }
        if let ahead = display.ahead {
            MapPolyline(ahead.casing)
                .stroke(display.casingColor, style: tripShapeStroke(
                    width: TripFocusMapLayer.Style.coreWidth + TripFocusMapLayer.Style.casingExtraWidth
                ))
            MapPolyline(ahead.core)
                .stroke(display.routeColor, style: tripShapeStroke(width: TripFocusMapLayer.Style.coreWidth))
        }

        ForEach(Array(display.arrows.enumerated()), id: \.offset) { _, arrow in
            Annotation("", coordinate: arrow.coordinate, anchor: .center) {
                TripDirectionArrow(headingDegrees: arrow.headingDegrees, color: display.arrowColor)
            }
        }

        ForEach(display.stops) { stop in
            Annotation("", coordinate: stop.coordinate, anchor: .center) {
                TripStopDot(stop: stop, routeColor: display.routeColor)
            }
        }

        // Debug, under the marker so the estimate stays on top.
        ForEach(reportedPositions) { position in
            Annotation("", coordinate: position.coordinate, anchor: .center) {
                Circle()
                    .stroke(Color(uiColor: position.kind.color), lineWidth: 2.5)
                    .frame(width: ReportedPositionAnnotationView.diameter, height: ReportedPositionAnnotationView.diameter)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
        }

        if let vehicle {
            Annotation("", coordinate: vehicle.coordinate, anchor: .center) {
                PanelVehicleMarker(
                    routeType: vehicle.routeType,
                    isRealTime: vehicle.isRealTime,
                    orientation: vehicle.orientation,
                    routeColor: display.routeColor,
                    staleness: vehicle.staleness
                )
                // The page's stop list already marks the stop the bus is at, and
                // the map tab's marker isn't interactive either.
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            }
        }
    }
}

func tripShapeStroke(width: CGFloat) -> StrokeStyle {
    StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
}

/// A chevron pointing the way a route runs, as `RouteArrowRenderer` draws it on the
/// map tab. Shared with `stopFocusMapContent(for:onSelectVehicle:)`.
struct TripDirectionArrow: View {
    let headingDegrees: CLLocationDirection
    let color: Color

    var body: some View {
        let size = RouteArrowStyle.extent * 2
        Path { path in
            path.addLines(RouteArrowStyle.chevron.map { CGPoint(x: $0.x + size / 2, y: $0.y + size / 2) })
        }
        .stroke(color, style: StrokeStyle(lineWidth: RouteArrowStyle.strokeWidth, lineCap: .round, lineJoin: .round))
        .frame(width: size, height: size)
        // The chevron points east unrotated, and compass headings run clockwise
        // from north, as a positive rotation does here.
        .rotationEffect(.degrees(headingDegrees - 90))
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

/// A vehicle on the panel's map, laid out as `PulsingVehicleAnnotationView` draws it
/// on the map tab: a route-colored dot with the mode's icon, gray when the position
/// is scheduled rather than live, a heading ring behind it when it's live, and
/// an uncertainty halo when it's an estimate from an aging fix.
///
/// Shared by the open trip's vehicle and an open stop's arriving vehicles. Callers
/// decide its accessibility and hit testing.
struct PanelVehicleMarker: View {
    let routeType: Route.RouteType
    let isRealTime: Bool
    /// In degrees, as OBA reports it.
    let orientation: CLLocationDirection
    let routeColor: Color
    /// How old the fix behind the position is; `.live` for a reported position.
    var staleness: VehicleMarkerStaleness = .live

    private static let diameter = TripFocusMapLayer.Style.vehicleDiameter

    var body: some View {
        let color = isRealTime ? routeColor : Color(uiColor: ThemeColors.shared.gray)

        ZStack {
            // The uncertainty halo of an estimate from an aging fix; see `VehicleMarkerStaleness`.
            if staleness.haloDiameter > 0 {
                Circle()
                    .fill(color.opacity(0.15))
                    .overlay(Circle().stroke(color.opacity(0.35), lineWidth: 1))
                    .frame(width: staleness.haloDiameter, height: staleness.haloDiameter)
            }
            if isRealTime && staleness.showsHeading {
                // Negated because OBA's orientation turns the other way from a
                // screen rotation; see `PulsingVehicleAnnotationView.updateHeading`.
                Image(uiImage: Icons.templateHeading)
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: Self.diameter * 3, height: Self.diameter * 3)
                    .foregroundStyle(color)
                    .rotationEffect(.radians(-orientation.radians))
            }
            Circle()
                .fill(color)
                .frame(width: Self.diameter, height: Self.diameter)
            Image(uiImage: Icons.transportIcon(from: routeType))
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: Self.diameter / 2, height: Self.diameter / 2)
                .foregroundStyle(.white)
        }
        .opacity(staleness.alpha)
    }
}
