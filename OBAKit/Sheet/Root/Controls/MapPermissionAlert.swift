//
//  MapPermissionAlert.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

// MARK: - MapPermissionAlert

/// An `.alert(...)` view modifier that surfaces the location-permission action
/// list corresponding to a `MapViewModel.TopPillState`. Attach it to the view
/// inside the presentation subtree that should host the alert — typically the
/// floating sheet's content builder in `MapPanelRootView`, so it presents on
/// top of the base sheet's `UISheetPresentationController` rather than
/// stealing the map layer's context.
///
/// `.alert` (rather than `.confirmationDialog`) is used deliberately: it does
/// not auto-inject a system Cancel button, so the "Keep Location Off" opt-out
/// stays the single, meaningful dismissal affordance. Confirmation dialogs
/// added a redundant Cancel row alongside "Keep Location Off".
///
/// The alert is driven by an optional `TopPillState` binding. Setting the
/// binding to a non-nil permission state presents; dismissal clears the
/// binding back to `nil`. The `.hidden` and `.zoomInForStops` cases are
/// no-ops and never trigger presentation.
struct MapPermissionAlert: ViewModifier {

    /// The set of actions the alert can dispatch. The caller decides how each
    /// maps to a concrete side effect (VM method, `UIApplication.open`, etc.).
    enum Action {
        case requestAuthorization
        case openSettings
        case requestPreciseLocation
    }

    @Binding var state: MapViewModel.TopPillState?
    let onAction: (Action) -> Void

    func body(content: Content) -> some View {
        content.alert(
            state.map(Self.title(for:)) ?? "",
            isPresented: isPresentedBinding,
            presenting: state
        ) { presented in
            buttons(for: presented)
        }
    }

    // MARK: - Bindings

    /// Bridges the optional state to the alert's `Bool` binding. Presentation
    /// is driven by the caller setting a non-nil value; dismissal writes
    /// `false`, which clears the state.
    private var isPresentedBinding: Binding<Bool> {
        Binding(
            get: { state != nil },
            set: { isPresented in
                if !isPresented { state = nil }
            }
        )
    }

    // MARK: - Title

    /// Copy of the alert title for a given permission state. Static because it
    /// depends only on the state — a pure formatting concern.
    private static func title(for state: MapViewModel.TopPillState) -> String {
        switch state {
        case .notDetermined:
            return OBALoc(
                "locationservices_alert_notdetermined.title",
                value: "Enable Location Services",
                comment: "Title of the alert asking the user to enable location services."
            )
        case .locationServicesOff:
            // NOTE: a distinct key from the UIKit `locationservices_alert_off.title`,
            // which is a `%@`-format string ("%@ works best with your location.")
            // consumed by `MapStatusView.alert(for:)`. Reusing that key here would
            // render the raw format string, stray `%@` and all, as the alert title.
            return OBALoc(
                "map_status_alert.location_services_off.title",
                value: "Location Services Off",
                comment: "Title of the alert shown when location services are disabled for the app."
            )
        case .impreciseLocation:
            // Distinct key from the UIKit `locationservices_alert_imprecise.title`
            // format string, for the same reason as `.locationServicesOff` above.
            return OBALoc(
                "map_status_alert.precise_location_off.title",
                value: "Precise Location Off",
                comment: "Title of the alert shown when the user has restricted the app to reduced-accuracy location."
            )
        case .hidden, .zoomInForStops, .locationServicesUnavailable:
            return ""
        }
    }

    // MARK: - Buttons

    /// Actions rendered inside the alert for a given state. Button labels
    /// mirror the UIKit `MapViewController.didTapMapStatus` alert. The
    /// "Keep …" buttons carry a `.cancel` role so they double as the alert's
    /// explicit dismissal — no phantom Cancel row appears.
    @ViewBuilder
    private func buttons(for state: MapViewModel.TopPillState) -> some View {
        switch state {
        case .notDetermined:
            Button(Strings.continue) { onAction(.requestAuthorization) }
            keepLocationOffButton
        case .locationServicesOff:
            Button(OBALoc(
                "locationservices_alert_gotosettings.button",
                value: "Turn On in Settings",
                comment: "Button that opens iOS Settings so the user can enable location services for the app."
            )) { onAction(.openSettings) }
            keepLocationOffButton
        case .impreciseLocation:
            Button(OBALoc(
                "locationservices_alert_gotosettings.button",
                value: "Turn On in Settings",
                comment: "Button that opens iOS Settings so the user can enable location services for the app."
            )) { onAction(.openSettings) }
            Button(OBALoc(
                "locationservices_alert_request_precise_location_once.button",
                value: "Allow Once",
                comment: "Button that grants one-time full-accuracy location for the current map session while keeping the default reduced-accuracy setting."
            )) { onAction(.requestPreciseLocation) }
            Button(OBALoc(
                "locationservices_alert_keep_precise_location_off.button",
                value: "Keep Precise Location Off",
                comment: "Cancel button in the precise-location alert; dismisses without raising accuracy from reduced to full."
            ), role: .cancel) {}
        case .hidden, .zoomInForStops, .locationServicesUnavailable:
            EmptyView()
        }
    }

    /// Shared cancel button used by both `.notDetermined` and
    /// `.locationServicesOff`. Extracted so the localized string and role live
    /// in one place — translators only need context for it once.
    private var keepLocationOffButton: some View {
        Button(OBALoc(
            "locationservices_alert_keepoff.button",
            value: "Keep Location Off",
            comment: "Cancel button in the location-permission alert; dismisses without granting authorization or opening Settings."
        ), role: .cancel) {}
    }
}

// MARK: - View extension

extension View {
    /// Attaches a `MapPermissionAlert` bound to `state`. Set the binding to a
    /// non-nil permission state (`.notDetermined`, `.locationServicesOff`,
    /// `.impreciseLocation`) to present; dismissal clears the binding.
    func mapPermissionAlert(
        state: Binding<MapViewModel.TopPillState?>,
        onAction: @escaping (MapPermissionAlert.Action) -> Void
    ) -> some View {
        modifier(MapPermissionAlert(state: state, onAction: onAction))
    }
}
