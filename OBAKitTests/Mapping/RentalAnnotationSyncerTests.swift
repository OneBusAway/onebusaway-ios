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
}
