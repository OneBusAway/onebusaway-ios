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
        let closeUser = CLLocation(latitude: 47.6097, longitude: -122.3331)
        #expect(WalkTimeInfo.compute(from: closeUser, to: stopLocation, speedMetersPerSecond: 1.4) == nil)
    }

    @Test func `WalkTimeInfo rounding behavior for exact minute boundary`() {
        // Distance ~84 meters at 1.4 m/s is ~60 seconds (1 minute)
        let user84m = CLLocation(latitude: 47.6097 + (84.0 / 111_000.0), longitude: -122.3331)
        let info = WalkTimeInfo.compute(from: user84m, to: stopLocation, speedMetersPerSecond: 1.4)

        #expect(info != nil)
        if let info {
            #expect(info.walkMinutes >= 1)
        }
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
