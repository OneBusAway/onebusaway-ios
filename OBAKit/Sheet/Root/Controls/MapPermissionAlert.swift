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
            Button(OBALoc(
                "locationservices_alert_keepoff.button",
                value: "Keep Location Off",
                comment: ""
            ), role: .cancel) {}
        case .locationServicesOff:
            Button(OBALoc(
                "locationservices_alert_gotosettings.button",
                value: "Turn On in Settings",
                comment: ""
            )) { onAction(.openSettings) }
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
            )) { onAction(.openSettings) }
            Button(OBALoc(
                "locationservices_alert_request_precise_location_once.button",
                value: "Allow Once",
                comment: ""
            )) { onAction(.requestPreciseLocation) }
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
