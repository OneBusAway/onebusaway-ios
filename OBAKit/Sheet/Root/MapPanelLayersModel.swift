//
//  MapPanelLayersModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OBAKitCore

/// The SwiftUI panel's window onto the map layer system.
///
/// `MapSheetView` writes through `MapRegionManager`, which owns the persistence
/// and posts notifications. This model turns those notifications into published
/// state so the panel's `Map` re-renders — the UIKit surface gets the same
/// effect from `MKMapView` delegate callbacks it has no counterpart to here.
///
/// Retains the registrar because `RegionsService` holds delegates weakly.
@MainActor final class MapPanelLayersModel: ObservableObject {

    @Published private(set) var isStopsLayerEnabled = true
    @Published private(set) var showsPointsOfInterest = true

    /// Drives the badge on the map-type button — the panel's only at-a-glance
    /// readout of layer state.
    @Published private(set) var enabledLayerCount = 0

    private let application: Application
    private var registrar: MapLayerRegistrar!

    init(application: Application) {
        self.application = application

        registrar = MapLayerRegistrar(application: application) { [weak self] _ in
            self?.refresh()
        }
        registrar.configure()

        let center = NotificationCenter.default
        for name in [
            Notification.Name.mapLayerEnabledStateDidChange,
            .mapLayerAvailabilityDidChange,
            .mapPointsOfInterestVisibilityDidChange,
            .rentalRangeFilterDidChange
        ] {
            center.addObserver(
                self,
                selector: #selector(refresh),
                name: name,
                object: nil
            )
        }

        refresh()
    }

    private var mapRegionManager: MapRegionManager { application.mapRegionManager }

    @objc private func refresh() {
        isStopsLayerEnabled = mapRegionManager.isStopsLayerEnabled
        showsPointsOfInterest = mapRegionManager.mapViewShowsPointsOfInterest
        enabledLayerCount = mapRegionManager.enabledMapLayerCount
    }

    /// Feeds the panel's camera into the layer pipeline. The `MKMapView` this
    /// manager owns is never laid out in panel mode, so nothing else would.
    func viewportDidChange(_ rect: MKMapRect) {
        mapRegionManager.mapLayersViewportDidChange(rect)
    }
}
