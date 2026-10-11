//
//  RentalTripPlan.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OBAKitCore
import OTPKit

/// "Plan a trip using this vehicle", shared by the UIKit map and the map panel so
/// the two cannot disagree about what the button plans or when it appears.
///
/// The vehicle is the trip's *origin*, in bike-rental mode. That is what rents it:
/// OTP's rental search starts with a walk to the nearest rentable vehicle, and
/// starting on top of this one makes it the nearest. Verified against Puget
/// Sound's server, where an origin at a Lime e-bike's coordinate with
/// `BICYCLE RENT` + `WALK` rents that exact vehicle id.
///
/// The previous shape — a via point at the vehicle with `.transitBikeRental` —
/// never produced a rental leg on that server: OTP treats a via point as a place
/// to pass, not a vehicle to pick up, and the plans walked straight past it.
enum RentalTripPlan {

    /// The mode the planner opens in.
    static let transportMode: TransportMode = .bikeRental

    /// The planner's origin: the vehicle's coordinate, titled with the label the
    /// rider just read on the sheet ("Lime e-bike"), so the origin field names
    /// the vehicle rather than a bare coordinate.
    static func origin(for rental: VehicleRental) -> MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: rental.coordinate))
        item.name = rental.displayLabel
        return item
    }

    /// Whether a bike-rental plan can use this rental at all.
    ///
    /// OTP's `BICYCLE RENT` rents bicycles only; scooter rental is a separate mode
    /// that Puget Sound's server answers with walk-only plans, and OTPKit offers no
    /// scooter mode to select. A button that plans a walk past the scooter the rider
    /// chose is worse than no button. Fail-open on missing typed data, matching the
    /// layer filter: an untyped vehicle or a station with no breakdown may be a bike.
    static func canPlan(using rental: VehicleRental) -> Bool {
        switch rental {
        case .vehicle(let vehicle):
            guard let formFactor = vehicle.vehicleType?.formFactor else { return true }
            return formFactor.isBicycle
        case .station(let station):
            return RentalFormat.stock(of: station) != .scooters
        }
    }

    /// Whether the region can open a trip planner — the predicate
    /// `MapViewController.showTripPlanner` and `TripPlannerSheetView` gate on.
    /// Checked up front so the sheets hide the button instead of offering one
    /// that dismisses the sheet and then silently does nothing.
    static func isTripPlanningAvailable(region: Region?, isTripPlanningEnabled: (Region) -> Bool) -> Bool {
        guard let region, region.supportsOTP else { return false }
        return isTripPlanningEnabled(region)
    }

    static func isTripPlanningAvailable(region: Region?, userDataStore: UserDataStore) -> Bool {
        isTripPlanningAvailable(region: region) { userDataStore.isTripPlanningEnabled(for: $0) }
    }
}
