//
//  RentalVisibilityTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import OTPKit
@testable import OBAKit

/// `RentalVisibility` holds every entity the source has delivered — not just the
/// visible ones — and answers "what should change on the map?" for each mutation.
/// The cache is what makes the range filter reversible: `VehicleRentalSource` emits
/// only diffs, so a dropped entity is not in a later `added` list.
@MainActor
@Suite(.serialized)
final class RentalVisibilityTests {

    private let scooters: Set<VehicleFormFactor> = [.scooter, .scooterSeated, .scooterStanding]
    private let bikes: Set<VehicleFormFactor> = [.bicycle, .cargoBicycle]

    // MARK: - Snapshot application

    @Test func addsMatchingEntities() throws {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(scooters)

        let scooter = try RentalFixtures.vehicle(id: "v1", formFactor: "SCOOTER")
        let changes = visibility.apply(RentalFixtures.snapshot(added: [scooter]))

        #expect(changes.added.map(\.id) == ["v1"])
        #expect(changes.removed.isEmpty)
    }

    @Test func ignoresEntitiesOfOtherFormFactors() throws {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(scooters)

        let bike = try RentalFixtures.vehicle(id: "b1", formFactor: "BICYCLE")
        let changes = visibility.apply(RentalFixtures.snapshot(added: [bike]))

        #expect(changes.isEmpty)
    }

    @Test func withNoFormFactorsNothingIsVisible() throws {
        var visibility = RentalVisibility()
        let scooter = try RentalFixtures.vehicle(id: "v1", formFactor: "SCOOTER")

        #expect(visibility.apply(RentalFixtures.snapshot(added: [scooter])).isEmpty)
    }

    @Test func removesEntities() throws {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(scooters)
        _ = visibility.apply(RentalFixtures.snapshot(added: [try RentalFixtures.vehicle(id: "v1")]))

        let changes = visibility.apply(RentalFixtures.snapshot(removed: ["v1"]))
        #expect(changes.removed == ["v1"])
    }

    @Test func removingAnInvisibleEntityChangesNothing() throws {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(scooters)
        _ = visibility.apply(RentalFixtures.snapshot(added: [try RentalFixtures.vehicle(id: "b1", formFactor: "BICYCLE")]))

        #expect(visibility.apply(RentalFixtures.snapshot(removed: ["b1"])).isEmpty)
    }

    @Test func duplicateAddIsIgnored() throws {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(scooters)
        let scooter = try RentalFixtures.vehicle(id: "v1")
        _ = visibility.apply(RentalFixtures.snapshot(added: [scooter]))

        #expect(visibility.apply(RentalFixtures.snapshot(added: [scooter])).isEmpty)
    }

    @Test func updatesVisibleEntityInPlace() throws {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(scooters)
        _ = visibility.apply(RentalFixtures.snapshot(added: [try RentalFixtures.vehicle(id: "v1", rangeMeters: 10_000)]))

        let changes = visibility.apply(RentalFixtures.snapshot(updated: [try RentalFixtures.vehicle(id: "v1", rangeMeters: 9_000)]))
        #expect(changes.updated.map(\.id) == ["v1"])
        #expect(changes.added.isEmpty)
        #expect(changes.removed.isEmpty)
    }

    // MARK: - Threshold crossing

    /// A scooter that drains below the threshold has to leave the map, and an
    /// update is not a way to leave — it must be emitted as a removal.
    @Test func updateCrossingBelowThresholdBecomesARemoval() throws {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(scooters)
        _ = visibility.apply(RentalFixtures.snapshot(added: [try RentalFixtures.vehicle(id: "v1", rangeMeters: 10_000)]))
        _ = visibility.setFilter(RentalRangeFilter(minimumRangeMeters: 8047))

        let changes = visibility.apply(RentalFixtures.snapshot(updated: [try RentalFixtures.vehicle(id: "v1", rangeMeters: 3_000)]))
        #expect(changes.removed == ["v1"])
        #expect(changes.updated.isEmpty)
    }

    /// The mirror image: fresh data lifting a vehicle above the threshold is an add.
    @Test func updateCrossingAboveThresholdBecomesAnAdd() throws {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(scooters)
        _ = visibility.setFilter(RentalRangeFilter(minimumRangeMeters: 8047))
        _ = visibility.apply(RentalFixtures.snapshot(added: [try RentalFixtures.vehicle(id: "v1", rangeMeters: 3_000)]))

        let changes = visibility.apply(RentalFixtures.snapshot(updated: [try RentalFixtures.vehicle(id: "v1", rangeMeters: 12_000)]))
        #expect(changes.added.map(\.id) == ["v1"])
        #expect(changes.updated.isEmpty)
    }

    @Test func updateStayingInvisibleChangesNothing() throws {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(scooters)
        _ = visibility.setFilter(RentalRangeFilter(minimumRangeMeters: 8047))
        _ = visibility.apply(RentalFixtures.snapshot(added: [try RentalFixtures.vehicle(id: "v1", rangeMeters: 1_000)]))

        #expect(visibility.apply(RentalFixtures.snapshot(updated: [try RentalFixtures.vehicle(id: "v1", rangeMeters: 2_000)])).isEmpty)
    }

    // MARK: - Filter changes

    @Test func raisingTheThresholdHidesShortRangeVehicles() throws {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(scooters)
        _ = visibility.apply(RentalFixtures.snapshot(added: [
            try RentalFixtures.vehicle(id: "near", rangeMeters: 3_000),
            try RentalFixtures.vehicle(id: "far", rangeMeters: 12_000)
        ]))

        let changes = visibility.setFilter(RentalRangeFilter(minimumRangeMeters: 8047))
        #expect(changes.removed == ["near"])
        #expect(changes.added.isEmpty)
    }

    /// The whole point of the cache: lowering the threshold restores vehicles
    /// without waiting for a refetch, because the source will not re-add them.
    @Test func loweringTheThresholdRestoresFromCache() throws {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(scooters)
        _ = visibility.apply(RentalFixtures.snapshot(added: [
            try RentalFixtures.vehicle(id: "near", rangeMeters: 3_000),
            try RentalFixtures.vehicle(id: "far", rangeMeters: 12_000)
        ]))
        _ = visibility.setFilter(RentalRangeFilter(minimumRangeMeters: 8047))

        let changes = visibility.setFilter(.any)
        #expect(changes.added.map(\.id) == ["near"])
        #expect(changes.removed.isEmpty)
    }

    @Test func settingTheSameFilterChangesNothing() throws {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(scooters)
        _ = visibility.apply(RentalFixtures.snapshot(added: [try RentalFixtures.vehicle(id: "v1", rangeMeters: 3_000)]))
        _ = visibility.setFilter(RentalRangeFilter(minimumRangeMeters: 8047))

        #expect(visibility.setFilter(RentalRangeFilter(minimumRangeMeters: 8047)).isEmpty)
    }

    /// Fail-open under a filter change too: stations and pedal bikes never leave.
    @Test func raisingTheThresholdKeepsStationsAndPedalBikes() throws {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(bikes)
        _ = visibility.apply(RentalFixtures.snapshot(added: [
            try RentalFixtures.station(id: "s1"),
            try RentalFixtures.pedalBike(id: "b1")
        ]))

        #expect(visibility.setFilter(RentalRangeFilter(minimumRangeMeters: 24_140)).isEmpty)
    }

    // MARK: - Form factor changes

    @Test func narrowingFormFactorsPrunes() throws {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(scooters.union(bikes))
        _ = visibility.apply(RentalFixtures.snapshot(added: [
            try RentalFixtures.vehicle(id: "v1", formFactor: "SCOOTER"),
            try RentalFixtures.vehicle(id: "b1", formFactor: "BICYCLE")
        ]))

        let changes = visibility.setFormFactors(scooters)
        #expect(changes.removed == ["b1"])
    }

    @Test func wideningFormFactorsRestoresFromCache() throws {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(scooters)
        _ = visibility.apply(RentalFixtures.snapshot(added: [
            try RentalFixtures.vehicle(id: "v1", formFactor: "SCOOTER"),
            try RentalFixtures.vehicle(id: "b1", formFactor: "BICYCLE")
        ]))

        let changes = visibility.setFormFactors(scooters.union(bikes))
        #expect(changes.added.map(\.id) == ["b1"])
    }

    @Test func clearingFormFactorsRemovesEverything() throws {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(scooters)
        _ = visibility.apply(RentalFixtures.snapshot(added: [
            try RentalFixtures.vehicle(id: "v1"),
            try RentalFixtures.vehicle(id: "v2")
        ]))

        let changes = visibility.setFormFactors([])
        #expect(changes.removed == ["v1", "v2"])
    }

    /// Wholesale recomputations sort by id, matching `VehicleRentalSource`'s own
    /// convention, so the emitted changes are reproducible.
    @Test func wholesaleChangesAreSortedByIdentifier() throws {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(scooters)
        _ = visibility.apply(RentalFixtures.snapshot(added: [
            try RentalFixtures.vehicle(id: "zebra", rangeMeters: 1_000),
            try RentalFixtures.vehicle(id: "alpha", rangeMeters: 1_000),
            try RentalFixtures.vehicle(id: "middle", rangeMeters: 1_000)
        ]))

        let changes = visibility.setFilter(RentalRangeFilter(minimumRangeMeters: 8047))
        #expect(changes.removed == ["alpha", "middle", "zebra"])
    }

    @Test func exposesCurrentFormFactorsAndFilter() {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(scooters)
        _ = visibility.setFilter(RentalRangeFilter(minimumRangeMeters: 5_000))

        #expect(visibility.formFactors == scooters)
        #expect(visibility.filter == RentalRangeFilter(minimumRangeMeters: 5_000))
    }
}
