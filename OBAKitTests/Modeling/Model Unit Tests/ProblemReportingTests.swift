//
//  ProblemReportingTests.swift
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

@Suite(.serialized)
final class ProblemReportingTests: OBATestCase {

    // MARK: - StopProblemCode Mapping

    @Test func `StopProblemCode string values match server API contract`() {
        #expect(StopProblemCode.nameWrong.APIStringValue == "stop_name_wrong")
        #expect(StopProblemCode.numberWrong.APIStringValue == "stop_number_wrong")
        #expect(StopProblemCode.locationWrong.APIStringValue == "stop_location_wrong")
        #expect(StopProblemCode.routeOrTripMissing.APIStringValue == "route_or_trip_missing")
        #expect(StopProblemCode.other.APIStringValue == "other")
    }

    // MARK: - TripProblemCode Mapping

    @Test func `TripProblemCode string values match server API contract`() {
        #expect(TripProblemCode.neverCame.APIStringValue == "vehicle_never_came")
        #expect(TripProblemCode.cameEarly.APIStringValue == "vehicle_came_early")
        #expect(TripProblemCode.cameLate.APIStringValue == "vehicle_came_late")
        #expect(TripProblemCode.wrongHeadsign.APIStringValue == "wrong_headsign")
        #expect(TripProblemCode.doesNotStopHere.APIStringValue == "vehicle_does_not_stop_here")
        #expect(TripProblemCode.other.APIStringValue == "other")
    }
}
