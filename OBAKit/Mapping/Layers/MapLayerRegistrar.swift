//
//  MapLayerRegistrar.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OBAKitCore
import OTPKit

/// Registers the map layers both surfaces share, and rebuilds the region-scoped
/// ones when the region changes.
///
/// `MapViewController` used to own all of this, which is why
/// `MapRegionManager.mapLayers` was empty whenever the SwiftUI panel was the
/// root — and why the Map sheet showed empty groups there. The overlay layers
/// (`StopRouteFocusMapLayer`, `TripFocusMapLayer`) deliberately stay in
/// `MapViewController`: they draw `MKOverlay` polylines the panel cannot render,
/// and their region-scoped `ShapeCache` rebuild is `MKMapView`-shaped.
///
/// Subclasses `NSObject` because `RegionsServiceDelegate` is an `@objc`
/// protocol. `RegionsService` holds delegates weakly, so the host must retain
/// this object or region changes will silently stop rebuilding layers.
@MainActor public final class MapLayerRegistrar: NSObject {

    private let application: Application

    /// Called after every `configure()`, so the host can re-wire whatever it
    /// hangs off the freshly-built layers (`MapViewController` re-points
    /// `actionsDelegate` and rebuilds its annotation syncer).
    private let onDidConfigure: (MapLayerRegistrar) -> Void

    /// The engine behind the rental layers, or nil when the current region has
    /// no bikeshare.
    public private(set) var rentalCoordinator: RentalLayerCoordinator?

    /// The rental layers built by the most recent `configure()`, in registration
    /// order: Bikes then Scooters.
    public private(set) var rentalLayers: [RentalMapLayer] = []

    public init(application: Application, onDidConfigure: @escaping (MapLayerRegistrar) -> Void) {
        self.application = application
        self.onDidConfigure = onDidConfigure
        super.init()
        application.regionsService.addDelegate(self)
    }

    private var mapRegionManager: MapRegionManager { application.mapRegionManager }

    /// Registers the stops layer once, then tears down and rebuilds the
    /// region-scoped rental layers. Safe to call repeatedly.
    public func configure() {
        if mapRegionManager.mapLayer(id: StopsMapLayer.layerID) == nil {
            mapRegionManager.registerMapLayer(StopsMapLayer(manager: mapRegionManager))
        }
        configureRentalLayers()
        onDidConfigure(self)
    }

    private func configureRentalLayers() {
        // Tear down any layers built for a previous region; preferences persist.
        mapRegionManager.removeMapLayer(id: RentalMapLayer.bikesLayerID)
        mapRegionManager.removeMapLayer(id: RentalMapLayer.scootersLayerID)
        rentalCoordinator = nil
        rentalLayers = []

        // Region flag = product enablement; the GraphQL service supplies the
        // capability. Whether the server actually works is decided by the first
        // fetch, which can dim the rows at runtime.
        guard let region = application.regionsService.currentRegion,
              region.isBikeshareEnabled,
              let graphQLURL = region.openTripPlannerGraphQLURL else {
            return
        }

        let service = GraphQLAPIService(baseURL: graphQLURL)
        let coordinator = RentalLayerCoordinator(service: service, locationService: application.locationService)
        rentalCoordinator = coordinator

        // Apply a filter chosen in a previous session before the first fetch,
        // rather than one notification late.
        coordinator.setRangeFilter(mapRegionManager.rentalRangeFilter)

        let bikes = RentalMapLayer.bikesLayer(coordinator: coordinator)
        let scooters = RentalMapLayer.scootersLayer(coordinator: coordinator)
        rentalLayers = [bikes, scooters]

        mapRegionManager.registerMapLayer(bikes)
        mapRegionManager.registerMapLayer(scooters)
    }
}

// MARK: - RegionsServiceDelegate

extension MapLayerRegistrar: RegionsServiceDelegate {
    public func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        configure()
    }

    /// A regions-list refresh can flip the current region's bikeshare fields in
    /// place without changing the region identity; re-evaluate the layers.
    public func regionsService(_ service: RegionsService, updatedRegionsList regions: [Region]) {
        configure()
    }
}
