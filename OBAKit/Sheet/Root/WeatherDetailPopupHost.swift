//
//  WeatherDetailPopupHost.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// UIKit-modal-hosted counterpart of the `WeatherDetailPopup` in
/// `MapPanelRootView`. Owns the presentation-state binding the card animates
/// against and forwards dismissal to the enclosing `UIHostingController`
/// via `@Environment(\.dismiss)` — so the SwiftUI exit transition plays
/// before UIKit tears the modal down.
///
/// `viewModel` is held as `@ObservedObject` (not a captured snapshot) so a
/// weather refresh that lands while the card is open updates the display in
/// place, matching the SwiftUI panel behavior (see `MapPanelRootView`).
struct WeatherDetailPopupHost: View {

    @ObservedObject var viewModel: MapViewModel

    /// Starts `false` and flips to `true` in `.onAppear` so SwiftUI sees a
    /// real state change and runs `WeatherDetailPopup`'s enter transition;
    /// initializing with `true` would skip the animation because SwiftUI
    /// only animates changes, not initial values. The call-site guard in
    /// `MapViewController.showWeather()` ensures `viewModel.weatherDisplay`
    /// is non-nil at present-time; if the forecast drops mid-open,
    /// `WeatherDetailPopup`'s own `onChange(of: display)` flips this back
    /// to `false` and the `onChange` below dismisses the host controller.
    /// The card also flips this back to `false` on backdrop tap or
    /// close-button press.
    @State private var isPresented = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        WeatherDetailPopup(display: viewModel.weatherDisplay, isPresented: $isPresented)
            .onChange(of: isPresented) { _, newValue in
                if !newValue { dismiss() }
            }
            .onAppear {
                isPresented = true
            }
    }
}
