//
//  RentalFormatTests.swift
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

/// The text that sits under a rental pin: battery percent when the feed provides
/// it, remaining range otherwise. On the launch feed `percent` is null fleet-wide
/// while `range` is populated, so the fallback is the common path, not the edge.
@MainActor
@Suite(.serialized)
final class RentalFormatTests {

    @Test func percentIsPreferredOverRange() throws {
        let rental = try RentalFixtures.vehicle(rangeMeters: 5470, batteryPercent: 0.62)
        #expect(RentalFormat.fuelLabelText(for: rental) == "62%")
    }

    @Test func percentRoundsToWholeNumber() throws {
        let rental = try RentalFixtures.vehicle(batteryPercent: 0.626)
        #expect(RentalFormat.fuelLabelText(for: rental) == "63%")
    }

    /// Feeds do send out-of-range values; clamp rather than render "120%".
    @Test func percentAboveOneClampsToHundred() throws {
        let rental = try RentalFixtures.vehicle(batteryPercent: 1.2)
        #expect(RentalFormat.fuelLabelText(for: rental) == "100%")
    }

    @Test func negativePercentClampsToZero() throws {
        let rental = try RentalFixtures.vehicle(batteryPercent: -0.1)
        #expect(RentalFormat.fuelLabelText(for: rental) == "0%")
    }

    @Test func fallsBackToRangeWhenPercentMissing() throws {
        let rental = try RentalFixtures.vehicle(rangeMeters: 5470, batteryPercent: nil)
        let text = RentalFormat.fuelLabelText(for: rental)
        #expect(text != nil)
        #expect(text?.contains("%") == false)
    }

    /// The default `MKDistanceFormatter` style spells the unit out ("3.4 miles"),
    /// which is far too long to sit under a map pin. The abbreviated style is the
    /// whole reason this formatter is separate from the detail sheet's.
    ///
    /// Comparing string contents against hardcoded English words ("miles") passes
    /// vacuously under a non-English host locale, where the spelled-out and
    /// abbreviated forms both differ from those words. Instead, build both styles
    /// from the same (ambient) locale and require the pin label to match the
    /// abbreviated one and differ from the spelled-out one — the second assertion
    /// is the one that actually catches a regression to the shared formatter.
    @Test func rangeFallbackUsesAbbreviatedUnits() throws {
        let rental = try RentalFixtures.vehicle(rangeMeters: 5470, batteryPercent: nil)
        let text = try #require(RentalFormat.fuelLabelText(for: rental))

        let abbreviated = MKDistanceFormatter()
        abbreviated.unitStyle = .abbreviated
        let spelledOut = MKDistanceFormatter()

        #expect(text == abbreviated.string(fromDistance: 5470))
        #expect(text != spelledOut.string(fromDistance: 5470))
    }

    @Test func noFuelDataYieldsNoLabel() throws {
        let rental = try RentalFixtures.vehicle(rangeMeters: nil, batteryPercent: nil)
        #expect(RentalFormat.fuelLabelText(for: rental) == nil)
    }

    @Test func pedalBikeYieldsNoLabel() throws {
        #expect(RentalFormat.fuelLabelText(for: try RentalFixtures.pedalBike()) == nil)
    }

    /// Stations have no fuel of their own; the docked vehicles do.
    @Test func stationYieldsNoLabel() throws {
        #expect(RentalFormat.fuelLabelText(for: try RentalFixtures.station()) == nil)
    }

    /// The detail sheet's formatter must keep its spelled-out style — this task
    /// adds a formatter rather than mutating the shared one.
    @Test func detailSheetFormatterIsUnchanged() {
        #expect(RentalFormat.distanceFormatter.unitStyle == .default)
        #expect(RentalFormat.abbreviatedDistanceFormatter.unitStyle == .abbreviated)
    }
}
