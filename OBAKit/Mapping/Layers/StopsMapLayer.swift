//
//  StopsMapLayer.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OBAKitCore

/// A thin `MapLayer` adapter over the existing stop pipeline, so bus stops appear
/// as a toggleable row in the Map sheet alongside the rental layers.
///
/// The stop pipeline predates the layer protocol and stays where it is: stops are
/// still fetched on region change (other surfaces, like the nearby list, read
/// `MapRegionManager.stops`), and the existing 40,000-height zoom gate still
/// applies. This adapter only controls whether stop *annotations* render.
@MainActor final class StopsMapLayer: NSObject, MapLayer {

    static let layerID = "stops"

    private weak var manager: MapRegionManager?

    init(manager: MapRegionManager) {
        self.manager = manager
        super.init()
    }

    // MARK: - MapLayer

    var id: String { Self.layerID }

    var title: String {
        OBALoc("map_layers.bus_stops", value: "Bus stops", comment: "Map sheet row for the transit stops layer")
    }

    var iconName: String { "bus.fill" }
    var tintColor: UIColor { ThemeColors.shared.brand }
    var group: MapLayerGroup { .transit }
    var isEnabledByDefault: Bool { true }
    var availability: MapLayerAvailability { .available }

    /// Shares `MapRegionManager.requiredHeightToShowStops` rather than mirroring
    /// the literal, so this layer and both map surfaces can't drift apart.
    var zoomWindow: MapLayerZoomWindow {
        MapLayerZoomWindow(maxVisibleHeight: MapRegionManager.requiredHeightToShowStops)
    }

    var densityBudget: Int { 250 }
    var isClusterable: Bool { false }
    var refreshPolicy: MapLayerRefreshPolicy { .onViewportChange }
    var staleAfter: Duration? { nil }

    func annotationView(for annotation: MKAnnotation, in mapView: MKMapView) -> MKAnnotationView? {
        // The existing viewFor pipeline renders stops; nothing to claim here.
        nil
    }

    func detailViewController(for annotation: MKAnnotation) -> UIViewController? {
        // Stop taps route through the existing StopViewController flow.
        nil
    }

    func activate() {
        manager?.stopsLayerVisibilityDidChange()
    }

    func deactivate() {
        manager?.stopsLayerVisibilityDidChange()
    }

    func viewportDidChange(_ mapRect: MKMapRect?) {
        // The existing stop pipeline already reacts to region changes.
    }

    func mapAnnotationsWereCleared() {
        // The existing stop pipeline re-adds stops via displayUniqueStopAnnotations.
    }
}
