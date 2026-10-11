//
//  RentalTripPlanTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import MapKit
import Testing
import OTPKit
@testable import OBAKit
@testable import OBAKitCore

/// "Plan a trip using this vehicle" starts the trip at the vehicle, in bike-rental
/// mode. Against Puget Sound's OTP server that rents the exact vehicle; the old
/// via-point request never produced a rental leg.
@MainActor
@Suite(.serialized)
struct RentalTripPlanTests {

    private static func region(otp: Bool, bikeshare: Bool = false) -> Region {
        Region(
            name: "Test",
            OBABaseURL: URL(string: "https://oba.example.com")!,
            coordinateRegion: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.33),
                latitudinalMeters: 50_000,
                longitudinalMeters: 50_000
            ),
            contactEmail: "test@example.com",
            openTripPlannerGraphQLURL: otp ? URL(string: "https://otp.example.com/otp/gtfs/v1") : nil,
            supportsOTPGraphQLBikeshare: bikeshare
        )
    }

    // MARK: - Request shape

    @Test func originIsTheVehicleNamedForTheRider() throws {
        let rental = try RentalFixtures.vehicle(formFactor: "BICYCLE", lat: 47.606753, lon: -122.33398)
        let origin = RentalTripPlan.origin(for: rental)

        #expect(origin.placemark.coordinate.latitude == 47.606753)
        #expect(origin.placemark.coordinate.longitude == -122.33398)
        #expect(origin.name == rental.displayLabel)
        #expect(RentalTripPlan.transportMode == .bikeRental)
    }

    // MARK: - Form factors

    @Test func bikesAndUntypedRentalsCanBePlanned() throws {
        #expect(RentalTripPlan.canPlan(using: try RentalFixtures.vehicle(formFactor: "BICYCLE")))
        #expect(RentalTripPlan.canPlan(using: try RentalFixtures.pedalBike()))
        #expect(RentalTripPlan.canPlan(using: try RentalFixtures.station()))
        #expect(RentalTripPlan.canPlan(using: try RentalFixtures.station(formFactors: ["BICYCLE", "SCOOTER"])))
    }

    /// OTP's bike-rental mode cannot rent a scooter; the planner would answer
    /// with a walk past it.
    @Test func scootersCannotBePlanned() throws {
        #expect(RentalTripPlan.canPlan(using: try RentalFixtures.vehicle(formFactor: "SCOOTER")) == false)
        #expect(RentalTripPlan.canPlan(using: try RentalFixtures.vehicle(formFactor: "SCOOTER_STANDING")) == false)
        #expect(RentalTripPlan.canPlan(using: try RentalFixtures.station(formFactors: ["SCOOTER"])) == false)
    }

    // MARK: - Availability

    /// The predicate `showTripPlanner` uses, asked up front so the button hides
    /// instead of dismissing the sheet into nothing.
    @Test func tripPlanningNeedsOTPAndTheRidersSetting() {
        let otpRegion = Self.region(otp: true)

        #expect(RentalTripPlan.isTripPlanningAvailable(region: otpRegion) { _ in true })
        #expect(RentalTripPlan.isTripPlanningAvailable(region: otpRegion) { _ in false } == false)
        #expect(RentalTripPlan.isTripPlanningAvailable(region: Self.region(otp: false)) { _ in true } == false)
        #expect(RentalTripPlan.isTripPlanningAvailable(region: nil) { _ in true } == false)
    }

    // MARK: - Rentals deep link

    @Test func rentalsLinkNeedsRentalLayersAndACoordinateInTheRegion() {
        let inside = CLLocationCoordinate2D(latitude: 47.61, longitude: -122.34)
        let outside = CLLocationCoordinate2D(latitude: 27.95, longitude: -82.46)

        #expect(Application.rentalsLinkApplies(to: Self.region(otp: true, bikeshare: true), coordinate: inside))
        #expect(Application.rentalsLinkApplies(to: Self.region(otp: true, bikeshare: true), coordinate: outside) == false)
        #expect(Application.rentalsLinkApplies(to: Self.region(otp: true, bikeshare: false), coordinate: inside) == false)
    }

    /// The landing zoom must be inside the rental layer's window, or the link
    /// would open on a map with no vehicles. MapKit fits the region to the view's
    /// narrower side, so allow for a portrait phone's ~2.2:1 height.
    @Test func rentalsLinkLandsWhereRentalsDraw() {
        let seattle = RentalMapLayer.focusRegion(around: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.33))
        let rect = MKMapRect(seattle)
        #expect(rect.height * 2.2 <= RentalMapLayer.maxVisibleHeight)
    }
}

/// "Zoom in to see bikes and scooters": shown between the rental window and the
/// stop window, only when a rental layer is on.
@Suite
struct RentalZoomHintTests {

    @Test func showsOnlyBetweenTheRentalAndStopThresholds() {
        #expect(MapRegionManager.shouldShowRentalZoomHint(forVisibleMapRectHeight: 10_000, rentalLayerEnabled: true) == false)
        #expect(MapRegionManager.shouldShowRentalZoomHint(forVisibleMapRectHeight: 20_000, rentalLayerEnabled: true) == false)
        #expect(MapRegionManager.shouldShowRentalZoomHint(forVisibleMapRectHeight: 20_001, rentalLayerEnabled: true))
        #expect(MapRegionManager.shouldShowRentalZoomHint(forVisibleMapRectHeight: 40_000, rentalLayerEnabled: true))
        // Past the stop threshold, "Zoom in for stops" already says it.
        #expect(MapRegionManager.shouldShowRentalZoomHint(forVisibleMapRectHeight: 40_001, rentalLayerEnabled: true) == false)
    }

    @Test func neverShowsWithRentalLayersOff() {
        #expect(MapRegionManager.shouldShowRentalZoomHint(forVisibleMapRectHeight: 30_000, rentalLayerEnabled: false) == false)
    }
}
