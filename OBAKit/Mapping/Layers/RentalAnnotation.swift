//
//  RentalAnnotation.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OTPKit

/// A rental entity (docked station or free-floating vehicle) on the main map.
///
/// Annotations are updated in place when a `VehicleRentalSnapshot` reports a
/// changed entity, so a selected callout survives refreshes instead of
/// flickering away.
public final class RentalAnnotation: NSObject, MKAnnotation {

    public private(set) var rental: VehicleRental

    /// KVO-compliant so MapKit animates in-place position updates.
    @objc public dynamic var coordinate: CLLocationCoordinate2D

    public var title: String? { rental.displayLabel }

    public var subtitle: String? {
        guard case .station(let station) = rental,
              let available = station.vehiclesAvailableCount else {
            return nil
        }
        return String(format: OBALoc("rental_annotation.vehicles_available_fmt",
                                     value: "%d available",
                                     comment: "Number of rental vehicles available at a station"), available)
    }

    /// Whether the view should render its fuel label.
    ///
    /// Set by `RentalLayerCoordinator` from the current zoom. It lives on the
    /// annotation rather than the view because `RentalMapLayer.annotationView(for:)`
    /// only dequeues a view and has no access to viewport state.
    public var showsFuelLabel: Bool = false

    public init(rental: VehicleRental) {
        self.rental = rental
        self.coordinate = rental.coordinate
        super.init()
    }

    /// Applies updated data in place, preserving identity (and thus selection).
    public func update(with rental: VehicleRental) {
        self.rental = rental
        if coordinate.latitude != rental.coordinate.latitude || coordinate.longitude != rental.coordinate.longitude {
            coordinate = rental.coordinate
        }
    }
}
