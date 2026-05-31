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

/// Describes the desired expansion state of the bottom panel / sheet (EC11).
/// UIKit maps each case to a `FloatingPanelState`; SwiftUI maps each case to a
/// `PresentationDetent` using the values below so the two layers stay in sync
/// on a single shared enum.
enum PanelDetent: Equatable {
    case tip
    case half
    case full

    /// SwiftUI presentation value for this detent. `.tip` pins to a fixed
    /// point height so the grabber stays a consistent size across devices;
    /// `.half` / `.full` scale with the containing view as fractions.
    /// Callers map this directly to `PresentationDetent.height(_:)` or
    /// `PresentationDetent.fraction(_:)`.
    enum Value: Equatable {
        case height(CGFloat)
        case fraction(Double)
    }

    var value: Value {
        switch self {
        case .tip:  return .height(120)
        case .half: return .fraction(0.5)
        case .full: return .fraction(1.0)
        }
    }
}

/// Shared ViewModel for the map bottom panel (nearby stops + search).
///
/// Consumed by `MapFloatingPanelController` (UIKit, via Combine `sink`) and by
/// future `HomeSheetView` (SwiftUI, via `@StateObject`).
@MainActor
class MapPanelViewModel: ObservableObject {

    // MARK: - Published State

    /// Desired panel/sheet expansion level. UIKit layer observes and calls `floatingPanel.move(to:)`;
    /// SwiftUI layer binds this to `presentationDetent` (EC11).
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
