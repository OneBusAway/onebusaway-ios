//
//  StopArrivalAccessibilityClockTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// `StopArrivalView` fills one `accessibilityTimeLabel` from two places — the
/// `arrivalDeparture` didSet and this content configuration — and at accessibility
/// text sizes that label is the only clock on screen. Both therefore have to carry
/// the timezone badge, which the configuration path did not until #1438.
///
/// The bundle pins the process to GMT (`OBATestCase`), so pointing `formatters`
/// at Los Angeles makes the offsets differ deterministically rather than relying
/// on where the test happens to run.
@MainActor
@Suite(.serialized)
struct StopArrivalAccessibilityClockTests {

    private func makeFormatters(timeZone: TimeZone) -> Formatters {
        let formatters = Formatters(
            locale: Locale(identifier: "en_US"),
            calendar: Calendar(identifier: .gregorian),
            themeColors: ThemeColors()
        )
        formatters.timeZone = timeZone
        return formatters
    }

    /// Carries `routeShortName` deliberately. `ArrivalDepartureItem.init` reads
    /// `routeAndHeadsign`, which falls through to `route.shortName` — an
    /// implicitly-unwrapped `Route` that only `loadReferences()` populates — when
    /// the denormalized name is absent. A fixture without it doesn't fail this
    /// test, it traps and takes the whole test runner with it.
    private func makeConfiguration(formatters: Formatters) throws -> ArrivalDepartureContentConfiguration {
        let epoch = 1_700_000_480
        let arrivalDeparture: ArrivalDeparture = try Fixtures.dictionaryToModel(
            type: ArrivalDeparture.self,
            dictionary: [
                "arrivalEnabled": true,
                "blockTripSequence": 1,
                "departureEnabled": true,
                "distanceFromStop": 100.0,
                "lastUpdateTime": epoch,
                "numberOfStopsAway": 1,
                "predicted": true,
                "predictedArrivalTime": epoch,
                "predictedDepartureTime": epoch,
                "routeId": "40_100479",
                "routeShortName": "1 Line",
                "scheduledArrivalTime": epoch,
                "scheduledDepartureTime": epoch,
                "serviceDate": epoch,
                "situationIds": [] as [String],
                "status": "default",
                "stopId": "stop_1",
                "stopSequence": 10,
                "totalStopsInTrip": 20,
                "tripHeadsign": "Lynnwood City Center",
                "tripId": "trip_north",
                "vehicleId": "vehicle_1"
            ]
        )
        let item = ArrivalDepartureItem(arrivalDeparture: arrivalDeparture, isAlarmAvailable: false)
        return ArrivalDepartureContentConfiguration(viewModel: item, formatters: formatters)
    }

    @Test func `Accessibility clock carries the badge when the region zone differs`() throws {
        let formatters = makeFormatters(timeZone: try #require(TimeZone(identifier: "America/Los_Angeles")))
        let config = try makeConfiguration(formatters: formatters)

        let label = try #require(config.accessibilityTimeLabelText)

        // The defect: `timeFormatter.string(from:)` renders a Pacific clock with
        // nothing saying so, and a GMT rider reads it as their own time.
        #expect(label != formatters.timeFormatter.string(from: config.viewModel.arrivalDepartureDate))
        #expect(label.contains("("))
        #expect(label == formatters.formattedClockTime(config.viewModel.arrivalDepartureDate))
    }

    @Test func `Accessibility clock stays bare when the rider shares the region zone`() throws {
        let formatters = makeFormatters(timeZone: try #require(TimeZone(identifier: "GMT")))
        let config = try makeConfiguration(formatters: formatters)

        let label = try #require(config.accessibilityTimeLabelText)

        // Same offset, so #332's badge would be noise — and this is the assertion
        // that stops the fix being "append a badge always".
        #expect(!label.contains("("))
        #expect(label == formatters.timeFormatter.string(from: config.viewModel.arrivalDepartureDate))
    }
}
