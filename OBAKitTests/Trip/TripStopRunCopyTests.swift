//
//  TripStopRunCopyTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import CoreLocation
import Foundation
import OBAKitCore
@testable import OBAKit

/// What a collapsed run of stops on the trip page says, on screen and to VoiceOver (#1576).
@Suite(.serialized)
struct TripStopRunCopyTests {

    private struct StopTimeStub: TripStopListEntry {
        let stopID: StopID
        let stopName: String
        let scheduledArrival: Date?
        var stopCoordinate: CLLocationCoordinate2D?
    }

    /// Stops A, B, C, … one minute apart; `timed: false` drops every time.
    private func groups(count: Int, userStop: StopID? = nil, vehicleAt: StopID, timed: Bool = true) -> [TripStopListModel.CollapsedGroup] {
        let stops = (0..<count).map { index in
            StopTimeStub(
                stopID: String(UnicodeScalar(65 + index)!),
                stopName: "Stop",
                scheduledArrival: timed ? Date(timeIntervalSince1970: Double(index) * 60) : nil
            )
        }
        return TripStopListModel.make(stopTimes: stops, userStopID: userStop, userStopSequence: nil, closestStopID: vehicleAt).groups
    }

    /// Minutes since the epoch, so the expected strings don't depend on a time zone.
    private func time(_ date: Date) -> String { "t\(Int(date.timeIntervalSince1970 / 60))" }

    @Test func `A run shows its count and time range`() throws {
        let group = try #require(groups(count: 8, vehicleAt: "F").first)

        #expect(TripStopRunCopy.title(for: group, time: time) == "5 stops • t0 – t4")
    }

    @Test func `A run with no times shows just its count`() throws {
        let group = try #require(groups(count: 8, vehicleAt: "F", timed: false).first)

        #expect(TripStopRunCopy.title(for: group, time: time) == "5 stops")
    }

    @Test func `VoiceOver hears what kind of run it is and when`() throws {
        let runs = groups(count: 12, userStop: "H", vehicleAt: "C")
        let passed = try #require(runs.first)
        let approaching = try #require(runs.last)

        #expect(TripStopRunCopy.accessibilityLabel(for: passed, time: time) == "2 passed stops, t0 to t1")
        #expect(TripStopRunCopy.accessibilityLabel(for: approaching, time: time) == "4 stops before your stop, t3 to t6")
    }

    @Test func `VoiceOver hears whether a run is expanded`() {
        #expect(TripStopRunCopy.accessibilityValue(isExpanded: false) == "collapsed")
        #expect(TripStopRunCopy.accessibilityValue(isExpanded: true) == "expanded")
    }

    /// The counts go through the stringsdict, so English reaches its singular.
    @Test func `Run counts resolve their singular`() {
        let bundle = Bundle.obaKit
        for key in ["trip_page.stop_list.run_count_fmt", "trip_page.stop_list.a11y_run_passed_fmt", "trip_page.stop_list.a11y_run_approaching_fmt"] {
            let format = bundle.localizedString(forKey: key, value: "MISSING", table: nil)
            let one = CountPlural.format(format, count: 1)
            #expect(one.hasPrefix("1 ") && !one.contains("stops"), "\(key) for 1: \(one)")
        }
    }
}
