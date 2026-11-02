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
        let title1 = TripCardView.routeToHeadsign("10", "Capitol Hill")
        #expect(title1 == "Route 10 to Capitol Hill")

        let title2 = TripCardView.routeToHeadsign("RapidRide E Line", "Downtown Seattle")
        #expect(title2 == "Route RapidRide E Line to Downtown Seattle")
    }

    @Test func testTripCardViewInitializationProperties() {
        let cardWithProvenance = TripCardView(
            departure: nil,
            routeShortName: "44",
            headsign: "Ballard",
            routeColor: .blue,
            routeTextColor: .white,
            provenance: "Scheduled trip"
        )

        #expect(cardWithProvenance.routeShortName == "44")
        #expect(cardWithProvenance.headsign == "Ballard")
        #expect(cardWithProvenance.provenance == "Scheduled trip")
        #expect(cardWithProvenance.departure == nil)
    }
}
