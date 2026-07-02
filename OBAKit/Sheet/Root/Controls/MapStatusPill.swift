//
//  MapStatusPill.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Top-center floating pill that surfaces the map's current status — either
/// "Zoom in for stops" (when the region is too broad to load stops) or a
/// location-permission prompt. Mirrors the UIKit `MapStatusView` but styled with
/// Liquid Glass. Renders nothing when there's no status to show.
///
/// The pill is display + tap only: it forwards permission-state taps to the
/// caller, which owns the `confirmationDialog` presentation. Presenting the
/// dialog from inside the pill (which lives in the map's overlay layer)
/// conflicts with `floatingSheet`'s always-presented `UISheetPresentationController`
/// and causes the base sheet to be dismissed. See `MapPanelRootView` for the
/// hosting side of the pattern.
struct MapStatusPill: View {
    let state: MapViewModel.TopPillState
    let onZoomInForStops: () -> Void
    let onPermissionTap: (MapViewModel.TopPillState) -> Void

    var body: some View {
        if let display = Display(state: state) {
            Button(action: handleTap) {
                HStack(spacing: 8) {
                    Image(systemName: display.symbolName)
                        .font(.headline)
                    Text(display.labelText)
                        .font(.headline)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .regularGlassEffectIfAvailable()
            .accessibilityLabel(Text(display.labelText))
        }
    }

    private func handleTap() {
        switch state {
        case .hidden:
            return
        case .zoomInForStops:
            onZoomInForStops()
        case .notDetermined, .locationServicesOff, .impreciseLocation:
            onPermissionTap(state)
        }
    }
}

// MARK: - Display

extension MapStatusPill {
    /// Presentation model for a single pill state. Split so the empty case
    /// (`.hidden`) simply returns `nil` and the view collapses to `EmptyView`.
    fileprivate struct Display {
        let symbolName: String
        let labelText: String

        init?(state: MapViewModel.TopPillState) {
            switch state {
            case .hidden:
                return nil
            case .zoomInForStops:
                symbolName = "plus.magnifyingglass"
                labelText = OBALoc(
                    "map_status_view.zoom_in_for_stops",
                    value: "Zoom in for stops",
                    comment: "Displayed in the map status view at the top of the map when the user must zoom in to see stops on the map"
                )
            case .notDetermined, .locationServicesOff:
                symbolName = "location.slash"
                labelText = OBALoc(
                    "map_status_view.location_services_unavailable",
                    value: "Location services unavailable",
                    comment: "Displayed in the map status view at the top of the map when the user has declined to give the app access to their location"
                )
            case .impreciseLocation:
                symbolName = "location.circle"
                labelText = OBALoc(
                    "map_status_view.precise_location_unavailable",
                    value: "Precise location unavailable",
                    comment: "Displayed in the map status view at the top of the map when the user has declined to give the app access to their precise location"
                )
            }
        }
    }
}
