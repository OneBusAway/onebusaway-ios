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
        #expect(OccupancyBadge.shortLabel(.empty) == OBALoc("occupancy_status.short.empty", value: "Empty", comment: ""))
        #expect(OccupancyBadge.shortLabel(.manySeatsAvailable) == OBALoc("occupancy_status.short.many_seats", value: "Many seats", comment: ""))
        #expect(OccupancyBadge.shortLabel(.fewSeatsAvailable) == OBALoc("occupancy_status.short.some_seats", value: "Some seats", comment: ""))
        #expect(OccupancyBadge.shortLabel(.standingRoomOnly) == OBALoc("occupancy_status.short.standing_room", value: "Standing room", comment: ""))
        #expect(OccupancyBadge.shortLabel(.crushedStandingRoomOnly) == OBALoc("occupancy_status.short.crowded", value: "Crowded", comment: ""))
        #expect(OccupancyBadge.shortLabel(.full) == OBALoc("occupancy_status.short.full", value: "Full", comment: ""))
        #expect(OccupancyBadge.shortLabel(.notBoardable) == OBALoc("occupancy_status.short.not_boarding", value: "Not boarding", comment: ""))
        #expect(OccupancyBadge.shortLabel(.notAcceptingPassengers) == OBALoc("occupancy_status.short.not_boarding", value: "Not boarding", comment: ""))
        #expect(OccupancyBadge.shortLabel(.noDataAvailable) == OBALoc("occupancy_status.short.unknown", value: "Unknown", comment: ""))
        #expect(OccupancyBadge.shortLabel(.unknown) == OBALoc("occupancy_status.short.unknown", value: "Unknown", comment: ""))
    }

    @Test func testLocalizedDescriptionMapping() {
        #expect(OccupancyBadge.localizedDescription(.empty) == OBALoc("occupancy_status.empty", value: "Empty", comment: ""))
        #expect(OccupancyBadge.localizedDescription(.manySeatsAvailable) == OBALoc("occupancy_status.many_seats_available", value: "Many seats available", comment: ""))
        #expect(OccupancyBadge.localizedDescription(.fewSeatsAvailable) == OBALoc("occupancy_status.few_seats_available", value: "Few seats available", comment: ""))
        #expect(OccupancyBadge.localizedDescription(.standingRoomOnly) == OBALoc("occupancy_status.standing_room_only", value: "Standing room only", comment: ""))
        #expect(OccupancyBadge.localizedDescription(.crushedStandingRoomOnly) == OBALoc("occupancy_status.crushed_standing_room_only", value: "Crushed standing room only", comment: ""))
        #expect(OccupancyBadge.localizedDescription(.full) == OBALoc("occupancy_status.full", value: "Full", comment: ""))
        #expect(OccupancyBadge.localizedDescription(.notBoardable) == OBALoc("occupancy_status.not_accepting_passengers", value: "Not accepting passengers", comment: ""))
        #expect(OccupancyBadge.localizedDescription(.notAcceptingPassengers) == OBALoc("occupancy_status.not_accepting_passengers", value: "Not accepting passengers", comment: ""))
        #expect(OccupancyBadge.localizedDescription(.noDataAvailable) == OBALoc("occupancy_status.unknown", value: "Unknown", comment: ""))
        #expect(OccupancyBadge.localizedDescription(.unknown) == OBALoc("occupancy_status.unknown", value: "Unknown", comment: ""))
    }
}
