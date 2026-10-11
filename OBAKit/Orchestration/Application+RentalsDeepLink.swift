//
//  Application+RentalsDeepLink.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import MapKit
import OBAKitCore

/// `onebusaway://rentals?lat=…&lon=…`: open the map on bikes and scooters.
///
/// `Application` stashes the coordinate in `pendingRentalsCoordinate`, the way it
/// stashes a stop in `pendingStopID`; whichever map surface is installed takes it
/// with `claimPendingRentalsFocus()` — on appearing, or on `.rentalsDeepLinkPending`.
extension Application {

    /// Brings the map forward and tells whichever map surface is installed that a
    /// rentals focus is waiting.
    @MainActor
    func showMapForPendingRentals() {
        // The panel's map is always the root; `rootNavigateTo` would only log there.
        if viewRouter.rootController != nil {
            viewRouter.rootNavigateTo(page: .map)
        }
        notificationCenter.post(name: .rentalsDeepLinkPending, object: nil)
    }

    /// Hands the pending coordinate to a map that is ready to show it, switching
    /// the Bikes and Scooters layers on first so the vehicles the link promised are
    /// there when the camera lands.
    ///
    /// Returns nil, keeping the coordinate, while the region is still loading. A
    /// region without rental layers, or a coordinate outside it, drops the link
    /// with a log line: there is nothing honest to show.
    @MainActor
    func claimPendingRentalsFocus() -> CLLocationCoordinate2D? {
        guard let coordinate = pendingRentalsCoordinate,
              let region = regionsService.currentRegion else {
            return nil
        }
        pendingRentalsCoordinate = nil

        guard Self.rentalsLinkApplies(to: region, coordinate: coordinate) else { return nil }

        mapRegionManager.setMapLayerEnabled(true, id: RentalMapLayer.bikesLayerID)
        mapRegionManager.setMapLayerEnabled(true, id: RentalMapLayer.scootersLayerID)
        return coordinate
    }

    /// Whether a rentals link can show anything in `region`. Logs the reason when not.
    static func rentalsLinkApplies(to region: Region, coordinate: CLLocationCoordinate2D) -> Bool {
        guard region.isBikeshareEnabled else {
            Logger.info("Ignoring rentals deep link: region \(region.name) has no bike or scooter layers.")
            return false
        }
        guard region.serviceRect.contains(MKMapPoint(coordinate)) else {
            Logger.info("Ignoring rentals deep link: \(coordinate.latitude),\(coordinate.longitude) is outside region \(region.name).")
            return false
        }
        return true
    }
}

extension Notification.Name {
    /// Posted on `Application.notificationCenter` when an `onebusaway://rentals`
    /// link is waiting for a map to show it. Each map surface answers by calling
    /// `Application.claimPendingRentalsFocus()`.
    static let rentalsDeepLinkPending = Notification.Name("OBARentalsDeepLinkPending")
}
