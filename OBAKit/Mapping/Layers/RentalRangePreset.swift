//
//  RentalRangePreset.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// One rung of the Map sheet's minimum-range menu.
///
/// The stored preference is always metres; these rungs are the rider-facing
/// choices. Rung values are whole numbers in the rider's own units rather than a
/// metric ladder converted from miles, because "8 km" reads as a bug.
struct RentalRangePreset: Equatable, Identifiable {

    /// The threshold this rung selects. Zero is the "Any" rung.
    let meters: Int

    /// Rider-facing label: "Any", "5 mi", "10 km".
    let title: String

    var id: Int { meters }

    /// The ladder for a measurement system.
    ///
    /// `Locale.MeasurementSystem` is a struct, not an enum — it carries `.metric`,
    /// `.us`, and `.uk` but can be built from any BCP-47 identifier, so it can
    /// never be switched exhaustively. Miles are therefore the *explicit* case and
    /// metric the fallback: `.uk` genuinely wants miles (UK road distances are in
    /// miles), and anything unrecognized lands on metric, which is right for most
    /// of the world.
    static func presets(
        measurementSystem: Locale.MeasurementSystem = Locale.current.measurementSystem,
        locale: Locale = .current
    ) -> [RentalRangePreset] {
        let usesMiles = measurementSystem == .us || measurementSystem == .uk
        let unit: UnitLength = usesMiles ? .miles : .kilometers
        let values: [Double] = usesMiles ? [1, 2, 5, 10, 15] : [2, 5, 10, 15, 25]

        let anyRung = RentalRangePreset(
            meters: 0,
            title: OBALoc("map_sheet.minimum_range_any", value: "Any", comment: "Range filter menu option imposing no minimum range")
        )

        let formatter = Self.formatter(for: locale)

        return [anyRung] + values.map { value in
            let measurement = Measurement(value: value, unit: unit)
            return RentalRangePreset(
                meters: Int(measurement.converted(to: .meters).value.rounded()),
                title: formatter.string(from: measurement)
            )
        }
    }

    /// The rung closest to a stored metre value. Used only to highlight the menu
    /// selection — filtering keeps using the stored value, so a preference set in
    /// another locale is never silently rewritten.
    static func nearest(toMeters meters: Int, in presets: [RentalRangePreset]) -> RentalRangePreset? {
        presets.min { abs($0.meters - meters) < abs($1.meters - meters) }
    }

    /// `.providedUnit` suppresses both conversion and locale substitution, so the
    /// displayed number matches the rung exactly ("5 mi", not "8 km").
    private static func formatter(for locale: Locale) -> MeasurementFormatter {
        let formatter = MeasurementFormatter()
        formatter.locale = locale
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .medium
        formatter.numberFormatter.maximumFractionDigits = 0
        return formatter
    }
}
