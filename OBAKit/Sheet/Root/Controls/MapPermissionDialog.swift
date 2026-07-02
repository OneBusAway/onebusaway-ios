//
//  MapPermissionDialog.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

// MARK: - MapPermissionDialog

/// A `confirmationDialog` view modifier that surfaces the location-permission
/// action list corresponding to a `MapViewModel.TopPillState`. Attach it to
/// the view inside the presentation subtree that should host the dialog —
/// typically the floating sheet's content builder in `MapPanelRootView`, so
/// it presents on top of the base sheet's `UISheetPresentationController`
/// rather than stealing the map layer's context.
///
/// The dialog is driven by an optional `TopPillState` binding. Setting the
/// binding to a non-nil permission state presents; dismissal clears the
/// binding back to `nil`. The `.hidden` and `.zoomInForStops` cases are
/// no-ops and never trigger presentation.
struct MapPermissionDialog: ViewModifier {

    /// The set of actions the dialog can dispatch. The caller decides how each
    /// maps to a concrete side effect (VM method, `UIApplication.open`, etc.).
    enum Action {
        case requestAuthorization
        case openSettings
        case requestPreciseLocation
    }

    @Binding var state: MapViewModel.TopPillState?
    let onAction: (Action) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            state.map(Self.title(for:)) ?? "",
            isPresented: isPresentedBinding,
            titleVisibility: .visible,
            presenting: state
        ) { presented in
            buttons(for: presented)
        }
    }

    // MARK: - Bindings

    /// Bridges the optional state to the `confirmationDialog`'s Bool binding.
    /// Presentation is driven by the caller setting a non-nil value; dismissal
    /// (system Cancel, tap outside) writes `false`, which clears the state.
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

    /// Actions rendered inside the `confirmationDialog` for a given state.
    /// Button labels mirror the UIKit `MapViewController.didTapMapStatus` alert.
    @ViewBuilder
    private func buttons(for state: MapViewModel.TopPillState) -> some View {
        switch state {
        case .notDetermined:
            Button(Strings.continue) { onAction(.requestAuthorization) }
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
            )) { onAction(.openSettings) }
            Button(OBALoc(
                "locationservices_alert_keepoff.button",
                value: "Keep Location Off",
                comment: ""
            )) {}
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
            )) {}
        case .hidden, .zoomInForStops:
            EmptyView()
        }
    }
}

// MARK: - View extension

extension View {
    /// Attaches a `MapPermissionDialog` bound to `state`. Set the binding to a
    /// non-nil permission state (`.notDetermined`, `.locationServicesOff`,
    /// `.impreciseLocation`) to present; dismissal clears the binding.
    func mapPermissionDialog(
        state: Binding<MapViewModel.TopPillState?>,
        onAction: @escaping (MapPermissionDialog.Action) -> Void
    ) -> some View {
        modifier(MapPermissionDialog(state: state, onAction: onAction))
    }
}
