//
//  ArrivalDepartureTimeTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import OBAKitCore

@MainActor
@Suite(.serialized)
final class ArrivalDepartureTimeTests {

    /// Builds an `ArrivalDeparture` whose `arrivalDepartureDate` is `remaining`
    /// relative to now. `Fixtures.arrivalDeparture` decodes through a plain
    /// `JSONDecoder`, so reference-date values are what land on `scheduledArrival`
    /// (see the note on `.deferredToDate` in its doc comment).
    ///
    /// `.arriving` (`stopSequence != 0`) with `predicted == false` means
    /// `arrivalDepartureDate == scheduledArrival`: the branch the tests below
    /// reason about. Truncating `Int(remaining)` to seconds lands `remaining`
    /// in `[remaining, remaining - 1)`-style bounds (e.g. `-30s` stays past),
    /// which the expected values below account for.
    private func departure(remaining: TimeInterval, stopID: String = "1_100", tripID: String) throws -> ArrivalDeparture {
        let reference = Int(Date(timeIntervalSinceNow: remaining).timeIntervalSinceReferenceDate)
        return try Fixtures.arrivalDeparture(
            predicted: false,
            scheduledArrival: reference,
            scheduledDeparture: reference,
            stopSequence: 1,
            stopID: stopID,
            tripID: tripID
        )
    }

    // MARK: - temporalState

    @Test func `A departure that occurred 30 seconds ago is past, not present`() throws {
        let arrivalDeparture = try departure(remaining: -30, tripID: "trip_departed_30s_ago")

        #expect(arrivalDeparture.arrivalDepartureDate.timeIntervalSinceNow < 0)
        #expect(arrivalDeparture.temporalState == .past)
    }

    @Test func `A departure that occurred 61 seconds ago is past`() throws {
        let arrivalDeparture = try departure(remaining: -61, tripID: "trip_departed_61s_ago")

        #expect(arrivalDeparture.temporalState == .past)
    }

    @Test func `A departure in the near future is present`() throws {
        let arrivalDeparture = try departure(remaining: 30, tripID: "trip_departing_in_30s")

        #expect(arrivalDeparture.temporalState == .present)
    }

    @Test func `A departure further out is future`() throws {
        let arrivalDeparture = try departure(remaining: 300, tripID: "trip_departing_in_300s")

        #expect(arrivalDeparture.temporalState == .future)
    }

    // MARK: - arrivalDepartureMinutes

    @Test func `arrivalDepartureMinutes floors the minute containing the departure`() throws {
        // Any departure still inside the current minute is 0, and any elapsed
        // time after the departure is negative, so the `.past` boundary lands
        // on the departure itself.
        #expect(try departure(remaining: -30, tripID: "trip_a").arrivalDepartureMinutes == -1)
        #expect(try departure(remaining: -61, tripID: "trip_b").arrivalDepartureMinutes == -2)
        #expect(try departure(remaining: 30, tripID: "trip_c").arrivalDepartureMinutes == 0)
    }

    // MARK: - BookmarkArrivalsRequest.matching

    @Test func `BookmarkArrivalsRequest excludes a departure that happened within the last minute`() throws {
        let request = BookmarkArrivalsRequest(stopID: "1_100")
        let justDeparted = try departure(remaining: -30, tripID: "trip_departed_30s_ago")
        let upcoming = try departure(remaining: 300, tripID: "trip_departing_in_300s")

        let matched = request.matching([justDeparted, upcoming])

        #expect(matched.map(\.tripID) == ["trip_departing_in_300s"])
    }
}
