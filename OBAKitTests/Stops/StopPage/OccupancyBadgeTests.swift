//
//  OccupancyBadgeTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import OBAKitCore
@testable import OBAKit

@Suite(.serialized)
struct OccupancyBadgeTests {

    @Test func testFillLevelQuarterSteps() {
        #expect(OccupancyBadge.fillLevel(.empty) == 0.0)
        #expect(OccupancyBadge.fillLevel(.manySeatsAvailable) == 0.25)
        #expect(OccupancyBadge.fillLevel(.fewSeatsAvailable) == 0.5)
        #expect(OccupancyBadge.fillLevel(.standingRoomOnly) == 0.75)
        #expect(OccupancyBadge.fillLevel(.crushedStandingRoomOnly) == 1.0)
        #expect(OccupancyBadge.fillLevel(.full) == 1.0)
        #expect(OccupancyBadge.fillLevel(.notBoardable) == 1.0)
        #expect(OccupancyBadge.fillLevel(.notAcceptingPassengers) == 1.0)
        #expect(OccupancyBadge.fillLevel(.noDataAvailable) == 0.0)
        #expect(OccupancyBadge.fillLevel(.unknown) == 0.0)
    }

    @Test func testShortLabelMapping() {
        #expect(OccupancyBadge.shortLabel(.empty) == "Empty")
        #expect(OccupancyBadge.shortLabel(.manySeatsAvailable) == "Many seats")
        #expect(OccupancyBadge.shortLabel(.fewSeatsAvailable) == "Some seats")
        #expect(OccupancyBadge.shortLabel(.standingRoomOnly) == "Standing room")
        #expect(OccupancyBadge.shortLabel(.crushedStandingRoomOnly) == "Crowded")
        #expect(OccupancyBadge.shortLabel(.full) == "Full")
        #expect(OccupancyBadge.shortLabel(.notBoardable) == "Not boarding")
        #expect(OccupancyBadge.shortLabel(.notAcceptingPassengers) == "Not boarding")
        #expect(OccupancyBadge.shortLabel(.noDataAvailable) == "Unknown")
        #expect(OccupancyBadge.shortLabel(.unknown) == "Unknown")
    }

    @Test func testLocalizedDescriptionMapping() {
        #expect(OccupancyBadge.localizedDescription(.empty) == "Empty")
        #expect(OccupancyBadge.localizedDescription(.manySeatsAvailable) == "Many seats available")
        #expect(OccupancyBadge.localizedDescription(.fewSeatsAvailable) == "Few seats available")
        #expect(OccupancyBadge.localizedDescription(.standingRoomOnly) == "Standing room only")
        #expect(OccupancyBadge.localizedDescription(.crushedStandingRoomOnly) == "Crushed standing room only")
        #expect(OccupancyBadge.localizedDescription(.full) == "Full")
        #expect(OccupancyBadge.localizedDescription(.notBoardable) == "Not accepting passengers")
        #expect(OccupancyBadge.localizedDescription(.notAcceptingPassengers) == "Not accepting passengers")
        #expect(OccupancyBadge.localizedDescription(.noDataAvailable) == "Unknown")
        #expect(OccupancyBadge.localizedDescription(.unknown) == "Unknown")
    }
}
