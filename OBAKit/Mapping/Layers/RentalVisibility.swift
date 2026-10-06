//
//  RentalVisibility.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OTPKit

/// Which delivered rentals belong on the map.
///
/// Holds every entity `VehicleRentalSource` has delivered for the current viewport
/// — not just the visible ones — so relaxing a filter restores vehicles from cache
/// instead of waiting for a refetch. The source emits only diffs, so an entity
/// dropped for being under threshold would otherwise never come back.
///
/// Memory stays bounded without extra work: the source replaces its delivered set
/// wholesale on each fetch and reports everything absent as removed, so this cache
/// tracks the padded viewport rather than growing across a session.
///
/// No MapKit and no async: every mutation returns the exact changes to apply.
struct RentalVisibility {

    /// What the map must do to catch up with a mutation.
    struct Changes: Equatable {
        var added: [VehicleRental] = []
        var removed: [VehicleRental.ID] = []
        var updated: [VehicleRental] = []

        var isEmpty: Bool { added.isEmpty && removed.isEmpty && updated.isEmpty }
    }

    private var cache: [VehicleRental.ID: VehicleRental] = [:]
    private var visibleIDs: Set<VehicleRental.ID> = []

    private(set) var formFactors: Set<VehicleFormFactor> = []
    private(set) var filter: RentalRangeFilter = .any

    /// With no form factors selected, every layer is off and nothing is visible.
    ///
    /// Virtual stations never show: they are a feed's bookkeeping, not a place a
    /// rider can walk to and find a vehicle. See `VehicleRental.isVirtualStation`.
    private func isVisible(_ rental: VehicleRental) -> Bool {
        !formFactors.isEmpty
            && !rental.isVirtualStation
            && rental.matches(formFactors: formFactors)
            && filter.allows(rental)
    }

    // MARK: - Snapshot application

    mutating func apply(_ snapshot: VehicleRentalSnapshot) -> Changes {
        var changes = Changes()

        for id in snapshot.removed {
            cache.removeValue(forKey: id)
            if visibleIDs.remove(id) != nil {
                changes.removed.append(id)
            }
        }

        for rental in snapshot.added where cache[rental.id] == nil {
            cache[rental.id] = rental
            if isVisible(rental) {
                visibleIDs.insert(rental.id)
                changes.added.append(rental)
            }
        }

        for rental in snapshot.updated {
            cache[rental.id] = rental
            // An update that crosses the visibility boundary is an add or a
            // removal — never an update. Emitting it as an update would leave the
            // map showing a vehicle the rider has filtered out.
            switch (visibleIDs.contains(rental.id), isVisible(rental)) {
            case (true, true):
                changes.updated.append(rental)
            case (true, false):
                visibleIDs.remove(rental.id)
                changes.removed.append(rental.id)
            case (false, true):
                visibleIDs.insert(rental.id)
                changes.added.append(rental)
            case (false, false):
                break
            }
        }

        return changes
    }

    // MARK: - Selection changes

    mutating func setFormFactors(_ formFactors: Set<VehicleFormFactor>) -> Changes {
        guard formFactors != self.formFactors else { return Changes() }
        self.formFactors = formFactors
        return reconcile()
    }

    mutating func setFilter(_ filter: RentalRangeFilter) -> Changes {
        guard filter != self.filter else { return Changes() }
        self.filter = filter
        return reconcile()
    }

    /// Recomputes visibility across the whole cache. Sorted by id so the emitted
    /// changes are deterministic, mirroring `VehicleRentalSource`'s own convention
    /// of sorting its removed array.
    private mutating func reconcile() -> Changes {
        var changes = Changes()

        for id in cache.keys.sorted() {
            guard let rental = cache[id] else { continue }

            switch (visibleIDs.contains(id), isVisible(rental)) {
            case (true, false):
                visibleIDs.remove(id)
                changes.removed.append(id)
            case (false, true):
                visibleIDs.insert(id)
                changes.added.append(rental)
            case (true, true), (false, false):
                break
            }
        }

        return changes
    }
}

// MARK: - Virtual stations

extension VehicleRentalStation {
    /// Dock counts at or above this are sentinels, not docks.
    ///
    /// Dockless operators publish "virtual stations" so their free-floating fleet
    /// fits GBFS's station model, and report an effectively unlimited capacity for
    /// them. Puget Sound's Lime feed carries one, `lime_seattle:seattle` — named
    /// "Seattle", pinned at Westlake, with 0 vehicles and `spacesAvailable` 999999.
    /// Drawn, it is a purple "0" in the middle of downtown that rents nothing.
    /// No real dock bank comes within two orders of magnitude of this.
    static let virtualStationDockThreshold = 10_000

    /// True when either dock count the feed publishes is a sentinel. Both are
    /// checked: `docksAvailableCount` prefers the typed total, which a feed could
    /// leave sane while the legacy field carries the sentinel.
    var isVirtual: Bool {
        [availableSpaces?.total, spacesAvailable]
            .compactMap { $0 }
            .contains { $0 >= Self.virtualStationDockThreshold }
    }

    /// The open-dock count fit to show a rider: nil when the feed omits it or
    /// reports a sentinel, so "999999 Docks" can never reach the screen.
    var displayableDocksCount: Int? {
        guard !isVirtual, let docks = docksAvailableCount else { return nil }
        return docks
    }
}

extension VehicleRental {
    /// True for a dockless operator's virtual station. Vehicles are never virtual.
    var isVirtualStation: Bool {
        guard case .station(let station) = self else { return false }
        return station.isVirtual
    }
}
