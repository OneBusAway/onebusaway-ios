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

/// An `.alert(...)` view modifier shown when the rider taps the map's status
/// pill while location is off for the app (`TopPillState.locationServicesOff`).
/// iOS won't prompt again in that state, so the alert offers Settings. Where iOS
/// can still prompt, the pill raises the system prompt directly instead (see
/// `MapPanelRootView.handlePermissionTap`). Attach it to the view inside the
/// presentation subtree that should host the alert — typically the floating
/// sheet's content builder in `MapPanelRootView`, so it presents on top of the
/// base sheet's `UISheetPresentationController` rather than stealing the map
/// layer's context.
///
/// `.alert` (rather than `.confirmationDialog`) is used deliberately: it does
/// not auto-inject a system Cancel button, so the "Keep Location Off" opt-out
/// stays the single, meaningful dismissal affordance. Confirmation dialogs
/// added a redundant Cancel row alongside "Keep Location Off".
struct MapPermissionAlert: ViewModifier {

    @Binding var isPresented: Bool
    let onOpenSettings: () -> Void

    func body(content: Content) -> some View {
        // NOTE: a distinct key from the UIKit `locationservices_alert_off.title`,
        // which is a `%@`-format string ("%@ works best with your location.")
        // consumed by `MapStatusView.locationServicesOffAlert()`. Reusing that key
        // here would render the raw format string, stray `%@` and all, as the title.
        content.alert(
            OBALoc(
                "map_status_alert.location_services_off.title",
                value: "Location Services Off",
                comment: "Title of the alert shown when location services are disabled for the app."
            ),
            isPresented: $isPresented
        ) {
            // Labels mirror the UIKit `MapViewController.didTapMapStatus` alert.
            Button(OBALoc(
                "locationservices_alert_gotosettings.button",
                value: "Turn On in Settings",
                comment: "Button that opens iOS Settings so the user can enable location services for the app."
            ), action: onOpenSettings)
            // `.cancel` so it doubles as the alert's explicit dismissal; no
            // phantom Cancel row appears.
            Button(OBALoc(
                "locationservices_alert_keepoff.button",
                value: "Keep Location Off",
                comment: "Cancel button in the location-permission alert; dismisses without granting authorization or opening Settings."
            ), role: .cancel) {}
        }
    }
}

// MARK: - View extension

extension View {
    /// Attaches a `MapPermissionAlert`. Set `isPresented` to present it;
    /// dismissal clears it.
    func mapPermissionAlert(isPresented: Binding<Bool>, onOpenSettings: @escaping () -> Void) -> some View {
        modifier(MapPermissionAlert(isPresented: isPresented, onOpenSettings: onOpenSettings))
    }
}
