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
@testable import OBAKitCore

/// `RentalLayerCoordinator` publishes `visibleRentals` driven by visibility diffs
/// (coverage of `RentalVisibility` lives in `RentalVisibilityTests`). These tests
/// drive the coordinator directly through `apply(_:)`, which is exposed (not
/// `private`) for this purpose, and never `await` anything: `setLayer`/
/// `viewportDidChange` each fire off a detached `Task` that talks to
/// `VehicleRentalSource`, but a synchronous, `@MainActor` test body can't yield,
/// so those tasks never get a chance to run before the assertions do. That
/// isolates the filter and zoom-gate logic from the async fetch/debounce
/// pipeline entirely.
@MainActor
@Suite(.serialized)
final class RentalLayerCoordinatorTests {

    /// Suite-scoped rather than `UserDefaults()`, which is `.standard`: separate
    /// suites run concurrently, so standard defaults let one suite observe
    /// another's writes. Mirrors `OBATestCase.buildUserDefaults()`.
    private let userDefaults = UserDefaults(suiteName: "RentalLayerCoordinatorTests.\(UUID().uuidString)")!

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

    private func makeCoordinator() -> RentalLayerCoordinator {
        let locationManager = MockAuthorizedLocationManager(
            updateLocation: TestData.mockSeattleLocation,
            updateHeading: TestData.mockHeading
        )
        return RentalLayerCoordinator(
            service: StubVehicleRentalService(),
            locationService: LocationService(userDefaults: userDefaults, locationManager: locationManager)
        )
    }

    // MARK: - Filter behavior (the diagnostic core)

    @Test func `Adding vehicles publishes both rentals`() throws {
        let coordinator = makeCoordinator()
        coordinator.setLayer(id: "scooters", enabled: true, formFactors: scooters)

        coordinator.apply(RentalFixtures.snapshot(added: [
            try RentalFixtures.vehicle(id: "near", rangeMeters: 3_000),
            try RentalFixtures.vehicle(id: "far", rangeMeters: 12_000)
        ]))

        #expect(coordinator.visibleRentals.count == 2)
    }

    @Test func `Raising the threshold hides the short range vehicle`() throws {
        let coordinator = makeCoordinator()
        coordinator.setLayer(id: "scooters", enabled: true, formFactors: scooters)
        coordinator.apply(RentalFixtures.snapshot(added: [
            try RentalFixtures.vehicle(id: "near", rangeMeters: 3_000),
            try RentalFixtures.vehicle(id: "far", rangeMeters: 12_000)
        ]))

        coordinator.setRangeFilter(RentalRangeFilter(minimumRangeMeters: 8047))

        #expect(coordinator.visibleRentals.map(\.id) == ["far"])
    }

    /// The whole point of `RentalVisibility`'s cache: relaxing the filter restores
    /// the previously-hidden vehicle from cache, with no refetch involved.
    @Test func `Lowering the threshold restores the hidden vehicle`() throws {
        let coordinator = makeCoordinator()
        coordinator.setLayer(id: "scooters", enabled: true, formFactors: scooters)
        coordinator.apply(RentalFixtures.snapshot(added: [
            try RentalFixtures.vehicle(id: "near", rangeMeters: 3_000),
            try RentalFixtures.vehicle(id: "far", rangeMeters: 12_000)
        ]))
        coordinator.setRangeFilter(RentalRangeFilter(minimumRangeMeters: 8047))

        coordinator.setRangeFilter(.any)

        #expect(coordinator.visibleRentals.map(\.id).sorted() == ["far", "near"])
    }

    /// Fail-open: a vehicle whose feed omits `range` is never filterable into
    /// invisibility, matching `RentalRangeFilter.allows(_:)`'s documented contract.
    @Test func `Vehicle with no range data survives an active filter`() throws {
        let coordinator = makeCoordinator()
        coordinator.setLayer(id: "scooters", enabled: true, formFactors: scooters)
        coordinator.setRangeFilter(RentalRangeFilter(minimumRangeMeters: 8047))

        coordinator.apply(RentalFixtures.snapshot(added: [
            try RentalFixtures.vehicle(id: "no-range-data", rangeMeters: nil)
        ]))

        #expect(coordinator.visibleRentals.map(\.id) == ["no-range-data"])
    }

    /// `visibleRentals` is sorted by id. `Array(dictionary.values)` has no
    /// guaranteed order, and an unstable order would reshuffle the panel's
    /// `ForEach` on every snapshot.
    @Test func `Publishes rentals sorted by id`() throws {
        let coordinator = makeCoordinator()
        coordinator.setLayer(id: "scooters", enabled: true, formFactors: scooters)

        coordinator.apply(RentalFixtures.snapshot(added: [
            try RentalFixtures.vehicle(id: "c"),
            try RentalFixtures.vehicle(id: "a"),
            try RentalFixtures.vehicle(id: "b")
        ]))

        #expect(coordinator.visibleRentals.map(\.id) == ["a", "b", "c"])
    }

    // MARK: - Fuel-label zoom gate

    @Test func `Small viewport shows fuel labels`() throws {
        let coordinator = makeCoordinator()
        coordinator.setLayer(id: "scooters", enabled: true, formFactors: scooters)
        coordinator.apply(RentalFixtures.snapshot(added: [try RentalFixtures.vehicle(id: "v1")]))

        // Well under the 8,000-map-point gate.
        coordinator.viewportDidChange(TestData.seattleMapRect)

        #expect(!coordinator.visibleRentals.isEmpty)
        #expect(coordinator.showsFuelLabels)
    }

    @Test func `Large viewport hides fuel labels`() throws {
        let coordinator = makeCoordinator()
        coordinator.setLayer(id: "scooters", enabled: true, formFactors: scooters)
        coordinator.apply(RentalFixtures.snapshot(added: [try RentalFixtures.vehicle(id: "v1")]))

        var largeRect = TestData.seattleMapRect
        largeRect.size.height = 10_000 // above the 8,000-map-point gate
        coordinator.viewportDidChange(largeRect)

        #expect(!coordinator.visibleRentals.isEmpty)
        #expect(!coordinator.showsFuelLabels)
    }

    @Test func `Closed zoom gate hides fuel labels`() throws {
        let coordinator = makeCoordinator()
        coordinator.setLayer(id: "scooters", enabled: true, formFactors: scooters)
        coordinator.apply(RentalFixtures.snapshot(added: [try RentalFixtures.vehicle(id: "v1")]))

        // Establish the "on" state first, so a passing test here can't be an
        // artifact of `showsFuelLabels` simply defaulting to false.
        coordinator.viewportDidChange(TestData.seattleMapRect)
        #expect(coordinator.showsFuelLabels)

        coordinator.viewportDidChange(nil)

        #expect(!coordinator.visibleRentals.isEmpty)
        #expect(!coordinator.showsFuelLabels)
    }
}
