//
//  MapViewportRecorder.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import OBAKitCore

/// Records the SwiftUI map panel's settled viewport into
/// `MapRegionManager.lastVisibleMapRect`.
///
/// The UIKit map writes that value from `mapView(_:regionDidChangeAnimated:)`, but
/// the manager's own `MKMapView` is never installed in the SwiftUI panel, so nothing
/// here keeps it current. Address and route searches use it *as the region they
/// query* (`SearchManager.fetchAddress` / `fetchRoute`), and its getter falls back to
/// the current region's whole service rect rather than `nil` — so a missing write
/// doesn't fail loudly, it just scopes searches to the wrong area.
///
/// A dedicated type rather than a method on `MapViewModel`: that view model
/// documents itself as containing no MapKit imports so it stays usable from both the
/// UIKit and SwiftUI hosts.
@MainActor
final class MapViewportRecorder {

    private let application: Application

    init(application: Application) {
        self.application = application
    }

    /// Persists `rect` as the panel's last visible viewport.
    func record(_ rect: MKMapRect) {
        application.mapRegionManager.lastVisibleMapRect = rect
    }
}
