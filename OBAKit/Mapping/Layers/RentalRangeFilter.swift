//
//  RentalRangeFilter.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OTPKit

/// The rider's "don't show me nearly-dead vehicles" filter.
///
/// Fail-open by design: only a vehicle that *reports* a range below the threshold
/// is hidden. Docked stations, pedal bikes, and vehicles whose feed omits `range`
/// all leave through the same early return — a feed that never publishes range
/// must not be filterable into an empty map. This mirrors the convention already
/// set by `VehicleRental.matches(formFactors:)`.
struct RentalRangeFilter: Equatable {

    /// Threshold in meters. Zero means "Any" — no filtering at all.
    let minimumRangeMeters: Int

    static let any = RentalRangeFilter(minimumRangeMeters: 0)

    var isActive: Bool { minimumRangeMeters > 0 }

    func allows(_ rental: VehicleRental) -> Bool {
        guard isActive,
              case .vehicle(let vehicle) = rental,
              let range = vehicle.fuel?.range else {
            return true
        }
        return range >= minimumRangeMeters
    }
}
