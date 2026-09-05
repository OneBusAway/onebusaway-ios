//
//  VehicleCoordinateUpdateTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import MapKit
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

    /// Farther than `snapBeyondMeters` (500 m) is a new fix, not motion.
    /// A ~1 km hop is well past that cliff — snaps rather than animating.
    @Test func `A jump beyond snapBeyondMeters snaps`() {
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

    // MARK: - apply(from:to:on:)

    @Test @MainActor func `Apply snap writes the destination coordinate`() {
        let annotation = MKPointAnnotation()
        annotation.coordinate = seattle
        let far = CLLocationCoordinate2D(latitude: 47.62, longitude: -122.33)

        VehicleCoordinateUpdate.apply(from: seattle, to: far, on: annotation)

        #expect(annotation.coordinate.latitude == far.latitude)
        #expect(annotation.coordinate.longitude == far.longitude)
    }

    @Test @MainActor func `Apply unchanged leaves the coordinate alone`() {
        let annotation = MKPointAnnotation()
        annotation.coordinate = seattle
        let almost = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.33211)

        VehicleCoordinateUpdate.apply(from: seattle, to: almost, on: annotation)

        #expect(annotation.coordinate.latitude == seattle.latitude)
        #expect(annotation.coordinate.longitude == seattle.longitude)
    }

    @Test @MainActor func `Apply animate eventually reaches the destination`() async {
        let annotation = MKPointAnnotation()
        annotation.coordinate = seattle

        VehicleCoordinateUpdate.apply(from: seattle, to: nearby, on: annotation)

        // Linear 0.8s animation; wait past it before asserting.
        try? await Task.sleep(for: .milliseconds(900))

        #expect(abs(annotation.coordinate.latitude - nearby.latitude) < 0.00001)
        #expect(abs(annotation.coordinate.longitude - nearby.longitude) < 0.00001)
    }
}
