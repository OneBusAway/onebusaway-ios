//
//  RentalLayerCoordinatorTests.swift
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
@testable import OBAKit

/// `RentalLayerCoordinator` is the seam between `RentalVisibility`'s pure diffing
/// (covered by `RentalVisibilityTests`) and the actual `MKMapView`. These tests drive
/// that seam directly through `apply(_:)`, which is exposed (not `private`) for this
/// purpose, and never `await` anything: `setLayer`/`viewportDidChange` each fire off
/// a detached `Task` that talks to `VehicleRentalSource`, but a synchronous,
/// `@MainActor` test body can't yield, so those tasks never get a chance to run
/// before the assertions do. That isolates the filter and zoom-gate logic from the
/// async fetch/debounce pipeline entirely.
@MainActor
@Suite(.serialized)
final class RentalLayerCoordinatorTests {

    /// Never actually called in these tests (no `await` reaches it), but the
    /// coordinator's initializer requires a `VehicleRentalService` to construct its
    /// `VehicleRentalSource`.
    private struct StubVehicleRentalService: VehicleRentalService {
        func fetchVehicleRentals(
            in boundingBox: VehicleRentalBoundingBox,
            formFactors: Set<VehicleFormFactor>?
        ) async throws -> VehicleRentalFetchResult {
            VehicleRentalFetchResult(rentals: [])
        }
    }

    private let scooters: Set<VehicleFormFactor> = [.scooter, .scooterSeated, .scooterStanding]

    private func makeCoordinator() -> (coordinator: RentalLayerCoordinator, mapView: MKMapView) {
        let mapView = MKMapView()
        let coordinator = RentalLayerCoordinator(service: StubVehicleRentalService(), mapView: mapView)
        return (coordinator, mapView)
    }

    /// `MKMapView.annotations` may include a user-location annotation, so tests must
    /// never assert on the raw count — only on rental annotations specifically.
    private func rentalAnnotations(_ mapView: MKMapView) -> [RentalAnnotation] {
        mapView.annotations.compactMap { $0 as? RentalAnnotation }
    }

    // MARK: - Filter behavior (the diagnostic core)

    @Test func addingVehiclesRendersBothAnnotations() throws {
        let (coordinator, mapView) = makeCoordinator()
        coordinator.setLayer(id: "scooters", enabled: true, formFactors: scooters)

        coordinator.apply(RentalFixtures.snapshot(added: [
            try RentalFixtures.vehicle(id: "near", rangeMeters: 3_000),
            try RentalFixtures.vehicle(id: "far", rangeMeters: 12_000)
        ]))

        #expect(rentalAnnotations(mapView).count == 2)
    }

    @Test func raisingTheThresholdHidesTheShortRangeVehicle() throws {
        let (coordinator, mapView) = makeCoordinator()
        coordinator.setLayer(id: "scooters", enabled: true, formFactors: scooters)
        coordinator.apply(RentalFixtures.snapshot(added: [
            try RentalFixtures.vehicle(id: "near", rangeMeters: 3_000),
            try RentalFixtures.vehicle(id: "far", rangeMeters: 12_000)
        ]))

        coordinator.setRangeFilter(RentalRangeFilter(minimumRangeMeters: 8047))

        let remaining = rentalAnnotations(mapView)
        #expect(remaining.count == 1)
        #expect(remaining.first?.rental.id == "far")
    }

    /// The whole point of `RentalVisibility`'s cache: relaxing the filter restores
    /// the previously-hidden vehicle from cache, with no refetch involved.
    @Test func loweringTheThresholdRestoresTheHiddenVehicle() throws {
        let (coordinator, mapView) = makeCoordinator()
        coordinator.setLayer(id: "scooters", enabled: true, formFactors: scooters)
        coordinator.apply(RentalFixtures.snapshot(added: [
            try RentalFixtures.vehicle(id: "near", rangeMeters: 3_000),
            try RentalFixtures.vehicle(id: "far", rangeMeters: 12_000)
        ]))
        coordinator.setRangeFilter(RentalRangeFilter(minimumRangeMeters: 8047))

        coordinator.setRangeFilter(.any)

        let restored = rentalAnnotations(mapView)
        #expect(restored.count == 2)
        #expect(Set(restored.map(\.rental.id)) == ["near", "far"])
    }

    /// Fail-open: a vehicle whose feed omits `range` is never filterable into
    /// invisibility, matching `RentalRangeFilter.allows(_:)`'s documented contract.
    @Test func vehicleWithNoRangeDataSurvivesAnActiveFilter() throws {
        let (coordinator, mapView) = makeCoordinator()
        coordinator.setLayer(id: "scooters", enabled: true, formFactors: scooters)
        coordinator.setRangeFilter(RentalRangeFilter(minimumRangeMeters: 8047))

        coordinator.apply(RentalFixtures.snapshot(added: [
            try RentalFixtures.vehicle(id: "no-range-data", rangeMeters: nil)
        ]))

        #expect(rentalAnnotations(mapView).map(\.rental.id) == ["no-range-data"])
    }

    // MARK: - Fuel-label zoom gate

    @Test func smallViewportShowsFuelLabels() throws {
        let (coordinator, mapView) = makeCoordinator()
        coordinator.setLayer(id: "scooters", enabled: true, formFactors: scooters)
        coordinator.apply(RentalFixtures.snapshot(added: [try RentalFixtures.vehicle(id: "v1")]))

        // Well under the 8,000-map-point gate.
        coordinator.viewportDidChange(TestData.seattleMapRect)

        let annotations = rentalAnnotations(mapView)
        #expect(!annotations.isEmpty)
        #expect(annotations.allSatisfy { $0.showsFuelLabel })
    }

    @Test func largeViewportHidesFuelLabels() throws {
        let (coordinator, mapView) = makeCoordinator()
        coordinator.setLayer(id: "scooters", enabled: true, formFactors: scooters)
        coordinator.apply(RentalFixtures.snapshot(added: [try RentalFixtures.vehicle(id: "v1")]))

        var largeRect = TestData.seattleMapRect
        largeRect.size.height = 10_000 // above the 8,000-map-point gate
        coordinator.viewportDidChange(largeRect)

        let annotations = rentalAnnotations(mapView)
        #expect(!annotations.isEmpty)
        #expect(annotations.allSatisfy { !$0.showsFuelLabel })
    }

    @Test func closedZoomGateHidesFuelLabels() throws {
        let (coordinator, mapView) = makeCoordinator()
        coordinator.setLayer(id: "scooters", enabled: true, formFactors: scooters)
        coordinator.apply(RentalFixtures.snapshot(added: [try RentalFixtures.vehicle(id: "v1")]))

        // Establish the "on" state first, so a passing test here can't be an
        // artifact of `showsFuelLabels` simply defaulting to false.
        coordinator.viewportDidChange(TestData.seattleMapRect)
        #expect(rentalAnnotations(mapView).allSatisfy { $0.showsFuelLabel })

        coordinator.viewportDidChange(nil)

        let annotations = rentalAnnotations(mapView)
        #expect(!annotations.isEmpty)
        #expect(annotations.allSatisfy { !$0.showsFuelLabel })
    }
}
