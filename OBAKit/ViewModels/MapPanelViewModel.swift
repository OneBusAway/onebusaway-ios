//
//  MapPanelViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Combine
import OBAKitCore

/// Desired expansion level for the map bottom panel's UIKit `FloatingPanel`.
/// `MapFloatingPanelController` maps each case to a `FloatingPanelState`.
enum PanelDetent: Equatable {
    case tip
    case half
    case full
}

/// Shared ViewModel for the map bottom panel (nearby stops + search).
///
/// Consumed by `MapFloatingPanelController` (UIKit, via Combine `sink`) and by
/// future `HomeSheetView` (SwiftUI, via `@StateObject`).
@MainActor
class MapPanelViewModel: ObservableObject {

    // MARK: - Published State

    /// Desired panel expansion level. Observed by `MapFloatingPanelController`, which
    /// calls `floatingPanel.move(to:)`.
    @Published var requestedPanelDetent: PanelDetent = .tip

    /// Nearby stops visible in the current map region.
    @Published private(set) var nearbyStops: [Stop] = []

    /// High-severity agency alerts to display as a banner.
    @Published private(set) var highSeverityAlerts: [AgencyAlert] = []

    // MARK: - Private

    private let application: Application

    // MARK: - Init

    init(application: Application) {
        self.application = application
        refreshAlerts()
    }

    // MARK: - Updates

    /// Called when MapRegionManager delivers updated nearby stops.
    func updateNearbyStops(_ stops: [Stop]) {
        nearbyStops = stops
    }

    /// Refreshes high-severity alerts from the store.
    func refreshAlerts() {
        highSeverityAlerts = application.alertsStore.recentHighSeverityAlerts
    }

    // MARK: - Search

    func enterSearchMode() {
        requestedPanelDetent = .full
    }

    func exitSearchMode() {
        requestedPanelDetent = .tip
    }
}
