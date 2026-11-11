//
//  WalkTimeInfoExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
@testable import OBAKit

/// Extended boundary tests for `WalkTimeInfo` distance thresholds,
/// negative speeds, and rounding behavior.
@MainActor
@Suite(.serialized)
final class WalkTimeInfoExtendedTests {

    private let stopLocation = CLLocation(latitude: 47.6097, longitude: -122.3331)

    @Test func `WalkTimeInfo compute returns nil when speed is negative or zero`() {
        let user = CLLocation(latitude: 47.6200, longitude: -122.3331)
        #expect(WalkTimeInfo.compute(from: user, to: stopLocation, speedMetersPerSecond: -1.4) == nil)
        #expect(WalkTimeInfo.compute(from: user, to: stopLocation, speedMetersPerSecond: 0) == nil)
    }

    @Test func `WalkTimeInfo distance within 40m threshold is suppressed as nil`() {
        // Distance <= 40m is suppressed to match nearby stop behavior
        let loc35m = CLLocation(latitude: 47.6097 + (35.0 / 111_000.0), longitude: -122.3331)
        #expect(loc35m.distance(from: stopLocation) < 40.0)
        #expect(WalkTimeInfo.compute(from: loc35m, to: stopLocation, speedMetersPerSecond: 1.4) == nil)

        let loc50m = CLLocation(latitude: 47.6097 + (50.0 / 111_000.0), longitude: -122.3331)
        #expect(loc50m.distance(from: stopLocation) > 40.0)
        #expect(WalkTimeInfo.compute(from: loc50m, to: stopLocation, speedMetersPerSecond: 1.4) != nil)
    }

    @Test func `WalkTimeInfo rounding behavior for exact minute boundary`() {
        let user = CLLocation(latitude: 47.6200, longitude: -122.3331)
        let distance = user.distance(from: stopLocation)

        // Case 1: Just below 60s (e.g. 59s -> ceil(59/60) = 1 min)
        let speed59s = distance / 59.0
        let info59s = WalkTimeInfo.compute(from: user, to: stopLocation, speedMetersPerSecond: speed59s)
        #expect(info59s?.walkMinutes == 1)

        // Case 2: Exactly 60s (60s -> ceil(60/60) = 1 min)
        let speed60s = distance / 60.0
        let info60s = WalkTimeInfo.compute(from: user, to: stopLocation, speedMetersPerSecond: speed60s)
        #expect(info60s?.walkMinutes == 1)

        // Case 3: Just above 60s (e.g. 61s -> ceil(61/60) = 2 min)
        let speed61s = distance / 61.0
        let info61s = WalkTimeInfo.compute(from: user, to: stopLocation, speedMetersPerSecond: speed61s)
        #expect(info61s?.walkMinutes == 2)
    }

    @Test func `WalkTimeInfo stores exact distance in meters`() {
        let user = CLLocation(latitude: 47.6200, longitude: -122.3331)
        let actualDist = user.distance(from: stopLocation)
        let info = WalkTimeInfo.compute(from: user, to: stopLocation, speedMetersPerSecond: 1.4)

        #expect(info != nil)
        if let info {
            #expect(abs(info.distance - actualDist) < 1.0)
        }
    }
}
