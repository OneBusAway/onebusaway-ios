//
//  ApproachSliceTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
@testable import OBAKit
import OBAKitCore

private struct StubStop: ApproachTimelineStop {
    let stopID: StopID
    let stopName: String
}

private func stops(_ ids: [String]) -> [StubStop] {
    ids.map { StubStop(stopID: $0, stopName: "Stop \($0)") }
}

final class ApproachSliceTests: XCTestCase {

    func test_takesFourUpstreamStopsPlusUserStop() {
        let slice = ApproachSlice.make(stopTimes: stops(["a", "b", "c", "d", "e", "f", "user"]), userStopID: "user", closestStopID: "d")
        XCTAssertEqual(slice?.stops.map(\.stopID), ["c", "d", "e", "f", "user"])
        XCTAssertEqual(slice?.vehicleIndex, 1) // "d" within the slice
        XCTAssertEqual(slice?.skippedStopCount, 0)
    }

    func test_shortTrip_usesAllAvailableUpstream() {
        let slice = ApproachSlice.make(stopTimes: stops(["a", "user"]), userStopID: "user", closestStopID: "a")
        XCTAssertEqual(slice?.stops.map(\.stopID), ["a", "user"])
        XCTAssertEqual(slice?.vehicleIndex, 0)
        XCTAssertEqual(slice?.skippedStopCount, 0)
    }

    func test_vehiclePastUserStop_returnsNil() {
        // Vehicle beyond the user's stop: timeline is meaningless, drop it.
        let slice = ApproachSlice.make(stopTimes: stops(["a", "user", "b"]), userStopID: "user", closestStopID: "b")
        XCTAssertNil(slice)
    }

    func test_vehicleBeyondWindow_pinsVehicleStopAndElidesGap() {
        // Vehicle is upstream but further back than the 4-stop window: its
        // stop pins to the top, "b"/"c" are elided, the 3 stops nearest the
        // user remain.
        let slice = ApproachSlice.make(stopTimes: stops(["a", "b", "c", "d", "e", "f", "user"]), userStopID: "user", closestStopID: "a")
        XCTAssertEqual(slice?.stops.map(\.stopID), ["a", "d", "e", "f", "user"])
        XCTAssertEqual(slice?.vehicleIndex, 0)
        XCTAssertEqual(slice?.skippedStopCount, 2)
    }

    func test_vehicleAtWindowEdge_hasNoGap() {
        // Vehicle exactly 4 stops upstream sits at the top of the contiguous
        // window; nothing is elided.
        let slice = ApproachSlice.make(stopTimes: stops(["a", "b", "c", "d", "e", "f", "user"]), userStopID: "user", closestStopID: "c")
        XCTAssertEqual(slice?.stops.map(\.stopID), ["c", "d", "e", "f", "user"])
        XCTAssertEqual(slice?.vehicleIndex, 0)
        XCTAssertEqual(slice?.skippedStopCount, 0)
    }

    func test_unknownClosestStop_hasNilVehicleIndex() {
        // closestStopID not on this trip at all: show the window, no bus dot.
        let slice = ApproachSlice.make(stopTimes: stops(["a", "b", "c", "d", "e", "f", "user"]), userStopID: "user", closestStopID: "zzz")
        XCTAssertEqual(slice?.stops.map(\.stopID), ["c", "d", "e", "f", "user"])
        XCTAssertNil(slice?.vehicleIndex)
        XCTAssertEqual(slice?.skippedStopCount, 0)
    }

    func test_userStopMissing_returnsNil() {
        XCTAssertNil(ApproachSlice.make(stopTimes: stops(["a", "b"]), userStopID: "user", closestStopID: "a"))
    }

    func test_nilClosestStop_stillShowsStops() {
        let slice = ApproachSlice.make(stopTimes: stops(["a", "b", "user"]), userStopID: "user", closestStopID: nil)
        XCTAssertEqual(slice?.stops.map(\.stopID), ["a", "b", "user"])
        XCTAssertNil(slice?.vehicleIndex)
        XCTAssertEqual(slice?.skippedStopCount, 0)
    }
}
