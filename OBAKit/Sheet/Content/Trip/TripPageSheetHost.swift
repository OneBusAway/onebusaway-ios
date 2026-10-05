//
//  TripPageSheetHost.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit
import OBAKitCore

/// Hosts `TripPageViewController` as the map panel's `AppSheetRoute.tripDetails`
/// sheet, so a trip opens over the panel's map instead of covering it.
///
/// Hosted bare, with no navigation controller around it: the page hides its
/// stack's bar, so a stop pushed onto one inside this sheet would have no way
/// back. The page's two navigation actions go to the panel instead. A tapped
/// stop opens the panel's stop sheet, and Back closes this one.
struct TripPageSheetHost: UIViewControllerRepresentable {
    let application: Application
    let tripConvertible: TripConvertible

    /// Hands the page's map focus to the panel's map. See
    /// `TripPageViewController.onMapFocusChanged`.
    let onMapFocusChanged: (TripMapFocus?) -> Void

    /// Opens a tapped stop. See `TripPageViewController.onSelectStop`.
    let onSelectStop: (StopID) -> Void

    /// Ends the sheet when the page's Back row is tapped. See
    /// `TripPageViewController.onClose`.
    let onClose: () -> Void

    func makeUIViewController(context: Context) -> TripPageViewController {
        Self.makeTripPage(
            application: application,
            tripConvertible: tripConvertible,
            onMapFocusChanged: onMapFocusChanged,
            onSelectStop: onSelectStop,
            onClose: onClose
        )
    }

    // The page's view model refreshes the trip itself, so nothing SwiftUI-side
    // changes over the sheet's lifetime.
    func updateUIViewController(_ uiViewController: TripPageViewController, context: Context) { }

    /// Internal factory seam, for the reason `MoreSheetHost.makeNavigationController`
    /// gives: tests can inspect the wiring without a `UIHostingController`.
    /// Production code goes through `makeUIViewController`.
    static func makeTripPage(
        application: Application,
        tripConvertible: TripConvertible,
        onMapFocusChanged: @escaping (TripMapFocus?) -> Void,
        onSelectStop: @escaping (StopID) -> Void,
        onClose: @escaping () -> Void
    ) -> TripPageViewController {
        let page = TripPageViewController(application: application, tripConvertible: tripConvertible)
        page.onMapFocusChanged = onMapFocusChanged
        page.onSelectStop = onSelectStop
        page.onClose = onClose
        return page
    }
}
