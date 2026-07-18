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
/// caller, which owns the `.alert` presentation. Presenting the alert from
/// inside the pill (which lives in the map's overlay layer) conflicts with
/// `floatingSheet`'s always-presented `UISheetPresentationController` and
/// causes the base sheet to be dismissed. See `MapPanelRootView` for the
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
        case .hidden, .locationServicesUnavailable:
            // `.locationServicesUnavailable` is a restricted/unknown status the
            // user can't resolve in Settings, so the pill is display-only.
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
    /// The symbol name and label come from the shared `MapStatusIndicator` so
    /// this pill and the UIKit `MapStatusView` can't drift.
    fileprivate struct Display {
        let symbolName: String
        let labelText: String

        init?(state: MapViewModel.TopPillState) {
            guard let indicator = MapStatusIndicator(state) else { return nil }
            symbolName = indicator.symbolName
            labelText = indicator.localizedText
        }
    }
}

// MARK: - TopPillState → MapStatusIndicator

extension MapStatusIndicator {
    /// Maps a pill state onto the shared indicator, or `nil` for states that
    /// render nothing (`.hidden`).
    fileprivate init?(_ state: MapViewModel.TopPillState) {
        switch state {
        case .hidden:
            return nil
        case .zoomInForStops:
            self = .zoomInForStops
        case .notDetermined, .locationServicesOff, .locationServicesUnavailable:
            self = .locationUnavailable
        case .impreciseLocation:
            self = .preciseLocationUnavailable
        }
    }
}
