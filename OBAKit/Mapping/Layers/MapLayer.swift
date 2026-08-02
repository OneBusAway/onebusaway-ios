//
//  MapLayer.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import UIKit

/// The group a layer belongs to in the Map sheet.
public enum MapLayerGroup {
    /// Transit data (bus stops, and eventually route lines and live vehicles).
    case transit
    /// Non-transit mobility (rental bikes, scooters).
    case otherModes
}

/// Whether a layer can currently show anything.
///
/// The three states drive the Map sheet's rendering rules: unsupported layers are
/// hidden, unavailable layers are dimmed with a reason, available layers are live.
/// Never show an enabled layer that cannot load — an empty layer switched on reads
/// as "there is nothing here," which is a lie.
public enum MapLayerAvailability: Equatable {
    /// The current region has no data source for this layer. Row hidden.
    case unsupported
    /// Configured, but the data source doesn't work right now (e.g. the first
    /// fetch failed). Row dimmed, with a rider-facing reason.
    case unavailable(reason: String)
    /// Working. Row live.
    case available
}

/// The zoom range in which a layer draws, expressed as visible-map-rect heights.
public struct MapLayerZoomWindow {
    /// The layer hides when the visible rect is taller than this (zoomed out too far).
    public let maxVisibleHeight: Double

    public init(maxVisibleHeight: Double) {
        self.maxVisibleHeight = maxVisibleHeight
    }

    public func contains(visibleHeight: Double) -> Bool {
        visibleHeight <= maxVisibleHeight
    }
}

/// How a layer's data refreshes.
public enum MapLayerRefreshPolicy: Equatable {
    /// Loaded once (e.g. static shapes).
    case `static`
    /// Refetched when the viewport changes. The default for browse layers.
    case onViewportChange
}

/// A toggleable data layer on the main map.
///
/// Layers register with `MapRegionManager`, which owns the on/off persistence
/// (`mapLayer.<id>.enabled` in UserDefaults), viewport forwarding, and zoom
/// gating. Each layer declares its own gating instead of hardcoding it into the
/// manager — rentals are the first conformer; route shapes, live vehicles, and
/// GTFS-Flex zones are expected to follow.
@MainActor public protocol MapLayer: AnyObject {
    /// Stable identifier; used as the persistence key suffix (`mapLayer.<id>.enabled`).
    var id: String { get }

    /// Rider-facing, localized title for the Map sheet row.
    var title: String { get }

    /// SF Symbol name for the Map sheet row.
    var iconName: String { get }

    var tintColor: UIColor { get }

    var group: MapLayerGroup { get }

    /// Whether the layer starts enabled the first time a rider sees it.
    var isEnabledByDefault: Bool { get }

    var availability: MapLayerAvailability { get }

    /// The zoom range in which this layer draws. Outside it, the manager passes a
    /// nil viewport and the layer removes its annotations.
    var zoomWindow: MapLayerZoomWindow { get }

    /// Max annotations before clustering must win. Declared, not enforced by the
    /// manager — the layer's own view configuration honors it.
    var densityBudget: Int { get }

    var isClusterable: Bool { get }

    var refreshPolicy: MapLayerRefreshPolicy { get }

    /// Age at which the layer's data should be treated as stale (drives freshness
    /// lines in detail sheets). Nil when staleness doesn't apply.
    var staleAfter: Duration? { get }

    /// Returns a configured annotation view when `annotation` belongs to this
    /// layer (including this layer's cluster annotations), nil otherwise. The
    /// manager tries each registered layer before its own annotation types.
    func annotationView(for annotation: MKAnnotation, in mapView: MKMapView) -> MKAnnotationView?

    /// Returns the detail UI for one of this layer's annotations, nil when the
    /// annotation isn't this layer's or has no detail surface.
    func detailViewController(for annotation: MKAnnotation) -> UIViewController?

    /// Begin feeding annotations onto the map.
    func activate()

    /// Remove all of this layer's annotations and cancel outstanding work.
    func deactivate()

    /// Called on every map region change while the layer is enabled. `mapRect` is
    /// nil when the viewport is outside `zoomWindow` — the layer removes its
    /// annotations in response, mirroring the stop pipeline's zoom gate.
    func viewportDidChange(_ mapRect: MKMapRect?)

    /// Called after something wiped the map wholesale (search flows call
    /// `removeAllAnnotations`). The layer re-adds any annotations it still
    /// considers delivered — without this, its bookkeeping and the map disagree
    /// and diffed updates mutate annotations that are no longer displayed.
    func mapAnnotationsWereCleared()
}

extension Notification.Name {
    /// Posted (object: the layer's `id`) when a layer's `availability` changes,
    /// so the Map sheet can re-render dimmed rows without polling.
    public static let mapLayerAvailabilityDidChange = Notification.Name("OBAMapLayerAvailabilityDidChange")

    /// Posted (object: the layer's `id`) when a layer is toggled on or off —
    /// drives the basemap button's active-layer count badge.
    public static let mapLayerEnabledStateDidChange = Notification.Name("OBAMapLayerEnabledStateDidChange")

    /// Posted when the shared rental minimum-range filter changes. Lets
    /// `MapViewController` push the new value into the rental coordinator without
    /// `MapRegionManager` needing to know the coordinator exists.
    public static let rentalRangeFilterDidChange = Notification.Name("OBARentalRangeFilterDidChange")

    /// Posted when Points of Interest visibility changes. Lets an open Map sheet
    /// refresh if Settings (or another writer) flips the same preference.
    public static let mapPointsOfInterestVisibilityDidChange = Notification.Name(
        "OBAMapPointsOfInterestVisibilityDidChange"
    )
}
