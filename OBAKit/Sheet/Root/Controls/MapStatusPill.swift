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
struct MapStatusPill: View {
    let state: MapViewModel.TopPillState
    let onZoomInForStops: () -> Void
    let onRequestAuthorization: () -> Void
    let onOpenSettings: () -> Void
    let onRequestPreciseLocation: () -> Void

    @State private var isPermissionDialogPresented = false

    var body: some View {
        if let display = Display(state: state) {
            Button(action: { handleTap(display: display) }) {
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
            .confirmationDialog(
                permissionDialogTitle(for: state),
                isPresented: $isPermissionDialogPresented,
                titleVisibility: .visible
            ) {
                permissionDialogButtons(for: state)
            }
        }
    }

    private func handleTap(display: Display) {
        switch state {
        case .hidden:
            return
        case .zoomInForStops:
            onZoomInForStops()
        case .notDetermined, .locationServicesOff, .impreciseLocation:
            isPermissionDialogPresented = true
        }
    }

    private func permissionDialogTitle(for state: MapViewModel.TopPillState) -> String {
        switch state {
        case .notDetermined:
            return OBALoc(
                "locationservices_alert_notdetermined.title",
                value: "Enable Location Services",
                comment: "Title of the alert asking the user to enable location services."
            )
        case .locationServicesOff:
            return OBALoc(
                "locationservices_alert_off.title",
                value: "Location Services Off",
                comment: "Title of the alert shown when location services are disabled for the app."
            )
        case .impreciseLocation:
            return OBALoc(
                "locationservices_alert_imprecise.title",
                value: "Precise Location Off",
                comment: "Title of the alert shown when the user has restricted the app to reduced-accuracy location."
            )
        case .hidden, .zoomInForStops:
            return ""
        }
    }

    @ViewBuilder
    private func permissionDialogButtons(for state: MapViewModel.TopPillState) -> some View {
        switch state {
        case .notDetermined:
            Button(Strings.continue) { onRequestAuthorization() }
            Button(OBALoc(
                "locationservices_alert_keepoff.button",
                value: "Keep Location Off",
                comment: ""
            )) {}
        case .locationServicesOff:
            Button(OBALoc(
                "locationservices_alert_gotosettings.button",
                value: "Turn On in Settings",
                comment: ""
            )) { onOpenSettings() }
            Button(OBALoc(
                "locationservices_alert_keepoff.button",
                value: "Keep Location Off",
                comment: ""
            ), role: .cancel) {}
        case .impreciseLocation:
            Button(OBALoc(
                "locationservices_alert_gotosettings.button",
                value: "Turn On in Settings",
                comment: ""
            )) { onOpenSettings() }
            Button(OBALoc(
                "locationservices_alert_request_precise_location_once.button",
                value: "Allow Once",
                comment: ""
            )) { onRequestPreciseLocation() }
            Button(OBALoc(
                "locationservices_alert_keep_precise_location_off.button",
                value: "Keep Precise Location Off",
                comment: ""
            ), role: .cancel) {}
        case .hidden, .zoomInForStops:
            EmptyView()
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
