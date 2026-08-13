//
//  RentalRangeFilterTests.swift
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

/// The rental minimum-range filter is deliberately fail-open: it hides only a
/// vehicle that *reports* a range below the threshold. Everything else — stations,
/// pedal bikes, vehicles whose feed omits range — stays on the map, so a feed that
/// never publishes range can't be filtered into an empty map.
@MainActor
@Suite(.serialized)
final class RentalRangeFilterTests {

    @Test func inactiveFilterAllowsEverything() throws {
        let filter = RentalRangeFilter.any

        #expect(filter.isActive == false)
        #expect(filter.allows(try RentalFixtures.vehicle(rangeMeters: 100)))
        #expect(filter.allows(try RentalFixtures.station()))
        #expect(filter.allows(try RentalFixtures.pedalBike()))
    }

    @Test func hidesVehicleBelowThreshold() throws {
        let filter = RentalRangeFilter(minimumRangeMeters: 8047)
        #expect(filter.allows(try RentalFixtures.vehicle(rangeMeters: 3200)) == false)
    }

    @Test func keepsVehicleAtExactlyThreshold() throws {
        let filter = RentalRangeFilter(minimumRangeMeters: 8047)
        #expect(filter.allows(try RentalFixtures.vehicle(rangeMeters: 8047)))
    }

    @Test func keepsVehicleAboveThreshold() throws {
        let filter = RentalRangeFilter(minimumRangeMeters: 8047)
        #expect(filter.allows(try RentalFixtures.vehicle(rangeMeters: 13000)))
    }

    @Test func keepsVehicleWithUnknownRange() throws {
        let filter = RentalRangeFilter(minimumRangeMeters: 8047)
        #expect(filter.allows(try RentalFixtures.vehicle(rangeMeters: nil)))
    }

    /// A battery percent is not a range; it must not be mistaken for one.
    @Test func keepsVehicleWithPercentButNoRange() throws {
        let filter = RentalRangeFilter(minimumRangeMeters: 8047)
        #expect(filter.allows(try RentalFixtures.vehicle(rangeMeters: nil, batteryPercent: 0.05)))
    }

    /// A pedal bike's range is the rider's legs. Filtering it out would be wrong.
    @Test func keepsPedalBike() throws {
        let filter = RentalRangeFilter(minimumRangeMeters: 8047)
        #expect(filter.allows(try RentalFixtures.pedalBike()))
    }

    @Test func keepsStation() throws {
        let filter = RentalRangeFilter(minimumRangeMeters: 8047)
        #expect(filter.allows(try RentalFixtures.station()))
    }
}
