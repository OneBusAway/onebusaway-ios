//
//  RentalAnnotationSyncerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import Testing
import OTPKit
import OBAKitCore
@testable import OBAKit

/// The syncer is the UIKit half of what `RentalLayerCoordinator` used to do
/// itself. Tests drive `sync(to:)` directly rather than through the Combine
/// subscription, which would need the run loop to turn.
@MainActor
@Suite(.serialized)
final class RentalAnnotationSyncerTests {

    /// Suite-scoped rather than `UserDefaults()`, which is `.standard`: separate
    /// suites run concurrently, so standard defaults let one suite observe
    /// another's writes. Mirrors `OBATestCase.buildUserDefaults()`.
    private let userDefaults = UserDefaults(suiteName: "RentalAnnotationSyncerTests.\(UUID().uuidString)")!

    private struct StubVehicleRentalService: VehicleRentalService {
        func fetchVehicleRentals(
            in boundingBox: VehicleRentalBoundingBox,
            formFactors: Set<VehicleFormFactor>?
        ) async throws -> VehicleRentalFetchResult {
            VehicleRentalFetchResult(rentals: [])
        }
    }

    private func makeSyncer() -> (syncer: RentalAnnotationSyncer, mapView: MKMapView) {
        let mapView = MKMapView()
        let locationManager = MockAuthorizedLocationManager(
            updateLocation: TestData.mockSeattleLocation,
            updateHeading: TestData.mockHeading
        )
        let coordinator = RentalLayerCoordinator(
            service: StubVehicleRentalService(),
            locationService: LocationService(userDefaults: userDefaults, locationManager: locationManager)
        )
        return (RentalAnnotationSyncer(coordinator: coordinator, mapView: mapView), mapView)
    }

    /// `MKMapView.annotations` may include a user-location annotation, so never
    /// assert on the raw count — only on rental annotations specifically.
    private func rentalAnnotations(_ mapView: MKMapView) -> [RentalAnnotation] {
        mapView.annotations.compactMap { $0 as? RentalAnnotation }
    }

    @Test func `Adds an annotation for each new rental`() throws {
        let (syncer, mapView) = makeSyncer()

        syncer.sync(to: [
            try RentalFixtures.vehicle(id: "a"),
            try RentalFixtures.vehicle(id: "b")
        ])

        #expect(Set(rentalAnnotations(mapView).map(\.rental.id)) == ["a", "b"])
    }

    @Test func `Removes annotations for rentals that left the list`() throws {
        let (syncer, mapView) = makeSyncer()
        syncer.sync(to: [
            try RentalFixtures.vehicle(id: "a"),
            try RentalFixtures.vehicle(id: "b")
        ])

        syncer.sync(to: [try RentalFixtures.vehicle(id: "a")])

        #expect(rentalAnnotations(mapView).map(\.rental.id) == ["a"])
    }

    /// Identity must survive an update, or MapKit drops the selection and any
    /// open callout every time the feed refreshes.
    @Test func `Reuses the same annotation object when a rental updates`() throws {
        let (syncer, mapView) = makeSyncer()
        syncer.sync(to: [try RentalFixtures.vehicle(id: "a", rangeMeters: 1_000)])
        let first = try #require(rentalAnnotations(mapView).first)

        syncer.sync(to: [try RentalFixtures.vehicle(id: "a", rangeMeters: 9_000)])
        let second = try #require(rentalAnnotations(mapView).first)

        #expect(first === second)
        #expect(rentalAnnotations(mapView).count == 1)
    }

    /// Search flows call `removeAllAnnotations`; without this the syncer's
    /// bookkeeping and the map disagree forever.
    @Test func `Reattaches tracked annotations after a wholesale clear`() throws {
        let (syncer, mapView) = makeSyncer()
        syncer.sync(to: [
            try RentalFixtures.vehicle(id: "a"),
            try RentalFixtures.vehicle(id: "b")
        ])
        mapView.removeAnnotations(mapView.annotations)
        #expect(rentalAnnotations(mapView).isEmpty)

        syncer.reattachAnnotations()

        #expect(Set(rentalAnnotations(mapView).map(\.rental.id)) == ["a", "b"])
    }

    @Test func `Reattaching twice does not duplicate annotations`() throws {
        let (syncer, mapView) = makeSyncer()
        syncer.sync(to: [try RentalFixtures.vehicle(id: "a")])

        syncer.reattachAnnotations()
        syncer.reattachAnnotations()

        #expect(rentalAnnotations(mapView).count == 1)
    }

    // MARK: - Transitions & Staleness Prevention

    @Test func `Syncing to empty list removes all annotations from mapView`() throws {
        let (syncer, mapView) = makeSyncer()
        syncer.sync(to: [
            try RentalFixtures.vehicle(id: "a"),
            try RentalFixtures.vehicle(id: "b")
        ])
        #expect(rentalAnnotations(mapView).count == 2)

        syncer.sync(to: [])
        #expect(rentalAnnotations(mapView).isEmpty)
    }

    @Test func `removeAll purges all annotations and clears tracking`() throws {
        let (syncer, mapView) = makeSyncer()
        syncer.sync(to: [
            try RentalFixtures.vehicle(id: "a"),
            try RentalFixtures.vehicle(id: "b")
        ])
        #expect(rentalAnnotations(mapView).count == 2)

        syncer.removeAll()
        #expect(rentalAnnotations(mapView).isEmpty)

        // reattach after removeAll should do nothing since tracking is cleared
        syncer.reattachAnnotations()
        #expect(rentalAnnotations(mapView).isEmpty)
    }

    @Test func `init purges pre-existing orphan rental annotations from mapView`() throws {
        let mapView = MKMapView()
        let orphan = RentalAnnotation(rental: try RentalFixtures.vehicle(id: "orphan"))
        mapView.addAnnotation(orphan)
        #expect(rentalAnnotations(mapView).count == 1)

        let locationManager = MockAuthorizedLocationManager(
            updateLocation: TestData.mockSeattleLocation,
            updateHeading: TestData.mockHeading
        )
        let coordinator = RentalLayerCoordinator(
            service: StubVehicleRentalService(),
            locationService: LocationService(userDefaults: userDefaults, locationManager: locationManager)
        )
        _ = RentalAnnotationSyncer(coordinator: coordinator, mapView: mapView)

        #expect(rentalAnnotations(mapView).isEmpty)
    }

    @Test func `Syncing to empty list purges untracked orphan rental annotations`() throws {
        let (syncer, mapView) = makeSyncer()
        let orphan = RentalAnnotation(rental: try RentalFixtures.vehicle(id: "orphan"))
        mapView.addAnnotation(orphan)
        #expect(rentalAnnotations(mapView).count == 1)

        syncer.sync(to: [])
        #expect(rentalAnnotations(mapView).isEmpty)
    }

    @Test func `Region change transition cleans up old annotations and adds new ones`() throws {
        let mapView = MKMapView()
        let locationManager = MockAuthorizedLocationManager(
            updateLocation: TestData.mockSeattleLocation,
            updateHeading: TestData.mockHeading
        )
        let coordinator1 = RentalLayerCoordinator(
            service: StubVehicleRentalService(),
            locationService: LocationService(userDefaults: userDefaults, locationManager: locationManager)
        )
        let syncer1 = RentalAnnotationSyncer(coordinator: coordinator1, mapView: mapView)
        syncer1.sync(to: [
            try RentalFixtures.vehicle(id: "r1_bike"),
            try RentalFixtures.vehicle(id: "r1_scooter")
        ])
        #expect(Set(rentalAnnotations(mapView).map(\.rental.id)) == ["r1_bike", "r1_scooter"])

        // Simulate region transition: old syncer is removed and new syncer created on same mapView
        syncer1.removeAll()
        let coordinator2 = RentalLayerCoordinator(
            service: StubVehicleRentalService(),
            locationService: LocationService(userDefaults: userDefaults, locationManager: locationManager)
        )
        let syncer2 = RentalAnnotationSyncer(coordinator: coordinator2, mapView: mapView)
        syncer2.sync(to: [try RentalFixtures.vehicle(id: "r2_bike")])

        #expect(rentalAnnotations(mapView).map(\.rental.id) == ["r2_bike"])
    }

    @Test func `Repeated reloads with same data preserve single annotation instances without duplicates`() throws {
        let (syncer, mapView) = makeSyncer()
        let vehicleA = try RentalFixtures.vehicle(id: "a", rangeMeters: 5_000)
        let vehicleB = try RentalFixtures.vehicle(id: "b", rangeMeters: 8_000)

        syncer.sync(to: [vehicleA, vehicleB])
        let firstA = try #require(rentalAnnotations(mapView).first(where: { $0.rental.id == "a" }))
        let firstB = try #require(rentalAnnotations(mapView).first(where: { $0.rental.id == "b" }))

        syncer.sync(to: [vehicleA, vehicleB])
        let secondA = try #require(rentalAnnotations(mapView).first(where: { $0.rental.id == "a" }))
        let secondB = try #require(rentalAnnotations(mapView).first(where: { $0.rental.id == "b" }))

        #expect(firstA === secondA)
        #expect(firstB === secondB)
        #expect(rentalAnnotations(mapView).count == 2)
    }

    @Test func `Hiding a service removes its annotations while preserving other services`() throws {
        let (syncer, mapView) = makeSyncer()
        let bike = try RentalFixtures.vehicle(id: "bike1", formFactor: "BICYCLE")
        let scooter = try RentalFixtures.vehicle(id: "scooter1", formFactor: "SCOOTER")

        syncer.sync(to: [bike, scooter])
        #expect(Set(rentalAnnotations(mapView).map(\.rental.id)) == ["bike1", "scooter1"])

        // Scooters service disabled/hidden
        syncer.sync(to: [bike])
        #expect(rentalAnnotations(mapView).map(\.rental.id) == ["bike1"])

        // Bikes service disabled/hidden
        syncer.sync(to: [])
        #expect(rentalAnnotations(mapView).isEmpty)
    }
}
