//
//  VehicleCoordinateUpdateTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Testing
import OBAKitCore
@testable import OBAKit

/// Policy for interpolating a vehicle marker between polls.
/// See: https://github.com/OneBusAway/onebusaway-ios/issues/1109
@Suite(.serialized)
struct VehicleCoordinateUpdateTests {

    private let seattle = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)

    /// ~45 m east of `seattle` — well inside one 15s poll at city speed.
    private var nearby: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3315)
    }

    /// GPS jitter: under 2 m, not worth restarting an animation.
    @Test func `Sub-meter jitter is unchanged`() {
        let almost = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.33211)
        #expect(VehicleCoordinateUpdate.decision(from: seattle, to: almost) == .unchanged)
    }

    @Test func `A city-block hop animates`() {
        let decision = VehicleCoordinateUpdate.decision(from: seattle, to: nearby)
        #expect(decision == .animate(duration: VehicleCoordinateUpdate.animationDuration))
    }

    /// Farther than `snapBeyondMeters` is a new fix, not motion.
    @Test func `A kilometre jump snaps`() {
        let far = CLLocationCoordinate2D(latitude: 47.62, longitude: -122.33)
        #expect(VehicleCoordinateUpdate.decision(from: seattle, to: far) == .snap)
    }

    @Test func `Null island snaps rather than interpolating across the ocean`() {
        #expect(VehicleCoordinateUpdate.decision(from: .init(), to: seattle) == .snap)
        #expect(VehicleCoordinateUpdate.decision(from: seattle, to: .init()) == .snap)
    }

    @Test func `An invalid coordinate snaps`() {
        #expect(VehicleCoordinateUpdate.decision(from: kCLLocationCoordinate2DInvalid, to: seattle) == .snap)
    }
}
