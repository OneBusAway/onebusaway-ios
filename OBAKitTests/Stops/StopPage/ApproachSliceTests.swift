//
//  ApproachSliceTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
@testable import OBAKit
import OBAKitCore

private struct StubStop: ApproachTimelineStop {
    let stopID: StopID
    let stopName: String
}

private func stops(_ ids: [String]) -> [StubStop] {
    ids.map { StubStop(stopID: $0, stopName: "Stop \($0)") }
}

@MainActor
@Suite(.serialized)
final class ApproachSliceTests {

    @Test func `Takes four upstream stops plus user stop`() {
        let slice = ApproachSlice.make(stopTimes: stops(["a", "b", "c", "d", "e", "f", "user"]), userStopID: "user", closestStopID: "d")
        #expect(slice?.stops.map(\.stopID) == ["c", "d", "e", "f", "user"])
        #expect(slice?.vehicleIndex == 1) // "d" within the slice
        #expect(slice?.skippedStopCount == 0)
    }

    @Test func `Short trip uses all available upstream`() {
        let slice = ApproachSlice.make(stopTimes: stops(["a", "user"]), userStopID: "user", closestStopID: "a")
        #expect(slice?.stops.map(\.stopID) == ["a", "user"])
        #expect(slice?.vehicleIndex == 0)
        #expect(slice?.skippedStopCount == 0)
    }

    @Test func `Vehicle past user stop returns nil`() {
        // Vehicle beyond the user's stop: timeline is meaningless, drop it.
        let slice = ApproachSlice.make(stopTimes: stops(["a", "user", "b"]), userStopID: "user", closestStopID: "b")
        #expect(slice == nil)
    }

    @Test func `Vehicle beyond window pins vehicle stop and elides gap`() {
        // Vehicle is upstream but further back than the 4-stop window: its
        // stop pins to the top, "b"/"c" are elided, the 3 stops nearest the
        // user remain.
        let slice = ApproachSlice.make(stopTimes: stops(["a", "b", "c", "d", "e", "f", "user"]), userStopID: "user", closestStopID: "a")
        #expect(slice?.stops.map(\.stopID) == ["a", "d", "e", "f", "user"])
        #expect(slice?.vehicleIndex == 0)
        #expect(slice?.skippedStopCount == 2)
    }

    @Test func `Vehicle at window edge has no gap`() {
        // Vehicle exactly 4 stops upstream sits at the top of the contiguous
        // window; nothing is elided.
        let slice = ApproachSlice.make(stopTimes: stops(["a", "b", "c", "d", "e", "f", "user"]), userStopID: "user", closestStopID: "c")
        #expect(slice?.stops.map(\.stopID) == ["c", "d", "e", "f", "user"])
        #expect(slice?.vehicleIndex == 0)
        #expect(slice?.skippedStopCount == 0)
    }

    @Test func `Unknown closest stop has nil vehicle index`() {
        // closestStopID not on this trip at all: show the window, no bus dot.
        let slice = ApproachSlice.make(stopTimes: stops(["a", "b", "c", "d", "e", "f", "user"]), userStopID: "user", closestStopID: "zzz")
        #expect(slice?.stops.map(\.stopID) == ["c", "d", "e", "f", "user"])
        #expect(slice?.vehicleIndex == nil)
        #expect(slice?.skippedStopCount == 0)
    }

    @Test func `User stop missing returns nil`() {
        #expect(ApproachSlice.make(stopTimes: stops(["a", "b"]), userStopID: "user", closestStopID: "a") == nil)
    }

    // MARK: - Loop routes

    @Test func `Loop route windows around the departures own visit`() {
        // "user" is visited twice (indices 1 and 5). The departure is for the
        // second visit, and the vehicle is between the two — so the window must
        // lead up to index 5, not collapse onto the first visit.
        let slice = ApproachSlice.make(
            stopTimes: stops(["a", "user", "b", "c", "d", "user", "e"]),
            userStopID: "user",
            userStopSequence: 5,
            closestStopID: "c"
        )
        #expect(slice?.stops.map(\.stopID) == ["user", "b", "c", "d", "user"])
        #expect(slice?.vehicleIndex == 2) // "c"
        #expect(slice?.skippedStopCount == 0)
    }

    @Test func `Loop route vehicle stop revisited uses occurrence before user stop`() {
        // The vehicle's closest stop ("a") also appears downstream of the user's
        // stop. The upstream occurrence is the leg the vehicle is actually on.
        let slice = ApproachSlice.make(
            stopTimes: stops(["a", "b", "user", "a", "c"]),
            userStopID: "user",
            userStopSequence: 2,
            closestStopID: "a"
        )
        #expect(slice?.stops.map(\.stopID) == ["a", "b", "user"])
        #expect(slice?.vehicleIndex == 0)
    }

    @Test func `Loop route vehicle past the departures visit returns nil`() {
        // Every occurrence of the vehicle's stop is downstream of this visit.
        let slice = ApproachSlice.make(
            stopTimes: stops(["a", "user", "b", "user", "c"]),
            userStopID: "user",
            userStopSequence: 1,
            closestStopID: "b"
        )
        #expect(slice == nil)
    }

    @Test func `Stale stop sequence falls back to stop ID search`() {
        // A sequence that doesn't point at the user's stop (out of range, or a
        // feed that numbers sequences differently) falls back to the first match.
        let slice = ApproachSlice.make(
            stopTimes: stops(["a", "b", "user"]),
            userStopID: "user",
            userStopSequence: 99,
            closestStopID: "a"
        )
        #expect(slice?.stops.map(\.stopID) == ["a", "b", "user"])
        #expect(slice?.vehicleIndex == 0)
    }

    @Test func `Nil closest stop still shows stops`() {
        let slice = ApproachSlice.make(stopTimes: stops(["a", "b", "user"]), userStopID: "user", closestStopID: nil)
        #expect(slice?.stops.map(\.stopID) == ["a", "b", "user"])
        #expect(slice?.vehicleIndex == nil)
        #expect(slice?.skippedStopCount == 0)
    }
}
