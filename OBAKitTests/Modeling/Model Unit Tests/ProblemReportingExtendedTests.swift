//
//  ProblemReportingExtendedTests.swift
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

/// Tests for `StopProblemCode` and `TripProblemCode` exhaustion,
/// user-friendly localized string retrieval, raw value stability, and round-trips.
@Suite(.serialized)
final class ProblemReportingExtendedTests: OBATestCase {

    // MARK: - StopProblemCode Case Completeness

    @Test func `StopProblemCode allCases contains exactly five documented problem types`() {
        let cases = StopProblemCode.allCases
        #expect(cases.count == 5)
        #expect(cases.contains(.nameWrong))
        #expect(cases.contains(.numberWrong))
        #expect(cases.contains(.locationWrong))
        #expect(cases.contains(.routeOrTripMissing))
        #expect(cases.contains(.other))
    }

    @Test func `StopProblemCode raw values are sequential integers`() {
        #expect(StopProblemCode.nameWrong.rawValue == 0)
        #expect(StopProblemCode.numberWrong.rawValue == 1)
        #expect(StopProblemCode.locationWrong.rawValue == 2)
        #expect(StopProblemCode.routeOrTripMissing.rawValue == 3)
        #expect(StopProblemCode.other.rawValue == 4)
    }

    @Test func `StopProblemCode userFriendlyStringValue returns non-empty descriptions`() {
        for code in StopProblemCode.allCases {
            let userString = code.userFriendlyStringValue
            #expect(!userString.isEmpty)
        }
    }

    @Test func `StopProblemCode mapping can be looked up from API strings`() {
        let mapping: [String: StopProblemCode] = Dictionary(
            uniqueKeysWithValues: StopProblemCode.allCases.map { ($0.APIStringValue, $0) }
        )

        #expect(mapping["stop_name_wrong"] == .nameWrong)
        #expect(mapping["stop_number_wrong"] == .numberWrong)
        #expect(mapping["stop_location_wrong"] == .locationWrong)
        #expect(mapping["route_or_trip_missing"] == .routeOrTripMissing)
        #expect(mapping["other"] == .other)
    }

    // MARK: - TripProblemCode Case Completeness

    @Test func `TripProblemCode allCases contains exactly six documented problem types`() {
        let cases = TripProblemCode.allCases
        #expect(cases.count == 6)
        #expect(cases.contains(.neverCame))
        #expect(cases.contains(.cameEarly))
        #expect(cases.contains(.cameLate))
        #expect(cases.contains(.wrongHeadsign))
        #expect(cases.contains(.doesNotStopHere))
        #expect(cases.contains(.other))
    }

    @Test func `TripProblemCode raw values are sequential integers`() {
        #expect(TripProblemCode.neverCame.rawValue == 0)
        #expect(TripProblemCode.cameEarly.rawValue == 1)
        #expect(TripProblemCode.cameLate.rawValue == 2)
        #expect(TripProblemCode.wrongHeadsign.rawValue == 3)
        #expect(TripProblemCode.doesNotStopHere.rawValue == 4)
        #expect(TripProblemCode.other.rawValue == 5)
    }

    @Test func `TripProblemCode userFriendlyStringValue returns non-empty descriptions`() {
        for code in TripProblemCode.allCases {
            let userString = code.userFriendlyStringValue
            #expect(!userString.isEmpty)
        }
    }

    @Test func `TripProblemCode mapping can be looked up from API strings`() {
        let mapping: [String: TripProblemCode] = Dictionary(
            uniqueKeysWithValues: TripProblemCode.allCases.map { ($0.APIStringValue, $0) }
        )

        #expect(mapping["vehicle_never_came"] == .neverCame)
        #expect(mapping["vehicle_came_early"] == .cameEarly)
        #expect(mapping["vehicle_came_late"] == .cameLate)
        #expect(mapping["wrong_headsign"] == .wrongHeadsign)
        #expect(mapping["vehicle_does_not_stop_here"] == .doesNotStopHere)
        #expect(mapping["other"] == .other)
    }
}
