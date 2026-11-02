//
//  AdjacentTripControllerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import Testing
import OBAKitCore
@testable import OBAKit

@MainActor
@Suite(.serialized)
final class AdjacentTripControllerTests {

    private func makeTrip(id: String, routeHeadsign: String) -> Trip {
        Trip(
            id: id,
            routeID: "1_100",
            tripHeadsign: routeHeadsign,
            serviceID: "1_wkdy",
            shapeID: "1_shape",
            directionID: "0",
            blockID: "1_block",
            routeShortName: "10",
            tripShortName: nil
        )
    }

    @Test func testAdjacentTripItemConfigurationMapping() {
        let trip = makeTrip(id: "trip_1", routeHeadsign: "Downtown")
        let item = AdjacentTripItem(order: .previous, trip: trip)

        #expect(item.id == "trip_1")
        #expect(item.order == .previous)
        #expect(item.trip == trip)

        guard case let .custom(config) = item.configuration else {
            Issue.record("Expected .custom configuration")
            return
        }

        guard let adjacentConfig = config as? AdjacentTripRowConfiguration else {
            Issue.record("Expected AdjacentTripRowConfiguration")
            return
        }

        #expect(adjacentConfig.order == .previous)
        #expect(adjacentConfig.routeHeadsign == "Downtown")
        #expect(adjacentConfig.obaContentView == TripStopCell.self)
    }

    @Test func testAdjacentTripItemEqualityAndHashing() {
        let tripA = makeTrip(id: "trip_A", routeHeadsign: "Downtown")
        let tripB = makeTrip(id: "trip_B", routeHeadsign: "Uptown")

        let itemPreviousA = AdjacentTripItem(order: .previous, trip: tripA)
        let itemNextA = AdjacentTripItem(order: .next, trip: tripA)
        let itemPreviousB = AdjacentTripItem(order: .previous, trip: tripB)

        #expect(itemPreviousA != itemNextA)
        #expect(itemPreviousA != itemPreviousB)

        var hasher1 = Hasher()
        itemPreviousA.hash(into: &hasher1)

        var hasher2 = Hasher()
        itemNextA.hash(into: &hasher2)

        #expect(hasher1.finalize() != hasher2.finalize())
    }

    @Test func testTripStopCellAppliesPreviousAdjacentTrip() {
        let cell = TripStopCell(frame: CGRect(x: 0, y: 0, width: 320, height: 60))
        let config = AdjacentTripRowConfiguration(order: .previous, routeHeadsign: "10 - Downtown Seattle")

        cell.apply(config)

        #expect(cell.titleLabel.text == "Starts as 10 - Downtown Seattle")
        #expect(cell.accessibilityLabel == "Starts as 10 - Downtown Seattle")
        #expect(cell.tripSegmentView.adjacentTripOrder == .previous)
    }

    @Test func testTripStopCellAppliesNextAdjacentTrip() {
        let cell = TripStopCell(frame: CGRect(x: 0, y: 0, width: 320, height: 60))
        let config = AdjacentTripRowConfiguration(order: .next, routeHeadsign: "49 - University District")

        cell.apply(config)

        #expect(cell.titleLabel.text == "Continues as 49 - University District")
        #expect(cell.accessibilityLabel == "Continues as 49 - University District")
        #expect(cell.tripSegmentView.adjacentTripOrder == .next)
    }
}
