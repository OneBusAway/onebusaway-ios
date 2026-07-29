//
//  DepartureStatusBridgeTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import OBAKitCore
@testable import OBAKit

/// Bridge tests over `DepartureStatus(arrivalDeparture:)` driven by real REST
/// fixtures rather than the hand-built values in `DepartureStatusTests`. They
/// verify the init forwards `predicted`/`scheduleStatus` correctly and that the
/// derived color and label stay consistent with the model's `scheduleStatus`.
@MainActor
@Suite(.serialized)
final class DepartureStatusBridgeTests {

    /// A live `ArrivalDeparture` (`predicted == true`) bridges to a real-time
    /// status: occupancy is shown and the color/label follow its `scheduleStatus`.
    @Test func `Realtime arrival departure is real time with consistent color and label`() throws {
        let arrivalDeparture = try Fixtures.loadRESTAPIPayload(
            type: ArrivalDeparture.self,
            fileName: "arrival-and-departure-for-stop-1_11420.json"
        )
        // Guard the fixture's real-time premise so a fixture change can't silently
        // reduce this to a scheduled-only case.
        #expect(arrivalDeparture.predicted)

        let status = DepartureStatus(arrivalDeparture: arrivalDeparture)
        #expect(status.isRealTime)
        #expect(status.showsOccupancy)
        assertColorAndLabelConsistent(status, with: arrivalDeparture.scheduleStatus)
    }

    /// A schedule-only `ArrivalDeparture` (`predicted == false`) bridges to the
    /// honesty state: no occupancy, gray, and the "schedule data" label that
    /// deliberately never claims the bus is "on time" (§4.1).
    @Test func `Scheduled only arrival departure is not real time with schedule data label`() throws {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals_and_departures_for_stop_1_10020_no_realtime.json"
        )
        let arrivalDeparture = try #require(stopArrivals.arrivalsAndDepartures.first)
        // Every entry in this fixture has `predicted == false`.
        #expect(!arrivalDeparture.predicted)

        let status = DepartureStatus(arrivalDeparture: arrivalDeparture)
        #expect(!status.isRealTime)
        #expect(!status.showsOccupancy)
        #expect(status.label == "schedule data")
        #expect(status.label != "on time")
        #expect(status.color == UIColor.secondaryLabel)
    }

    /// Asserts the real-time status' derived color and label agree with whatever
    /// `scheduleStatus` the model computed for the fixture.
    private func assertColorAndLabelConsistent(_ status: DepartureStatus, with scheduleStatus: ScheduleStatus) {
        switch scheduleStatus {
        case .onTime:
            #expect(status.color == ThemeColors.shared.departureOnTime)
            #expect(status.label == "on time")
        case .early:
            #expect(status.color == ThemeColors.shared.departureEarly)
            #expect(status.label.contains("early"))
        case .delayed:
            #expect(status.color == ThemeColors.shared.departureLate)
            #expect(status.label.contains("late"))
        case .unknown:
            #expect(status.color == UIColor.secondaryLabel)
            #expect(status.label == "schedule data")
        }
    }
}
