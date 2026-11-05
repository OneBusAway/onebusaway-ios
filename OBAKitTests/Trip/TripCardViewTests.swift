//
//  TripCardViewTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import Testing
import OBAKitCore
@testable import OBAKit

@MainActor
@Suite(.serialized)
final class TripCardViewTests {

    @Test func testRouteToHeadsignFormatting() {
        let fmt = OBALoc(
            "trip_page.card.a11y_no_arrival_fmt",
            value: "Route %@ to %@",
            comment: ""
        )

        let title1 = TripCardView.routeToHeadsign("10", "Capitol Hill")
        #expect(title1 == String(format: fmt, "10", "Capitol Hill"))

        let title2 = TripCardView.routeToHeadsign("RapidRide E Line", "Downtown Seattle")
        #expect(title2 == String(format: fmt, "RapidRide E Line", "Downtown Seattle"))
    }

    @Test func testAccessibilityTextFallbackWhenNoArrival() {
        let routeShortName = "44"
        let headsign = "Ballard"
        let provenance = "Scheduled trip"

        let cardWithProvenance = TripCardView(
            departure: nil,
            routeShortName: routeShortName,
            headsign: headsign,
            routeColor: .blue,
            routeTextColor: .white,
            provenance: provenance
        )

        let expectedTitle = TripCardView.routeToHeadsign(routeShortName, headsign)
        let expectedAccessibilityText = "\(expectedTitle), \(provenance)"

        let mirror = Mirror(reflecting: cardWithProvenance)
        let accessibilityText = mirror.descendant("accessibilityText") as? String
        #expect(accessibilityText == expectedAccessibilityText)

        let cardWithoutProvenance = TripCardView(
            departure: nil,
            routeShortName: routeShortName,
            headsign: headsign,
            routeColor: .blue,
            routeTextColor: .white,
            provenance: nil
        )

        let mirrorNoProv = Mirror(reflecting: cardWithoutProvenance)
        let accessibilityTextNoProv = mirrorNoProv.descendant("accessibilityText") as? String
        #expect(accessibilityTextNoProv == expectedTitle)
    }
}
