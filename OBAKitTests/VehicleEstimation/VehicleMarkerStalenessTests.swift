//
//  VehicleMarkerStalenessTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import MapKit
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class VehicleMarkerStalenessTests {
    private let here = CLLocationCoordinate2D(latitude: 47, longitude: -122)

    private func staleness(age: TimeInterval, mode: VehicleEstimate.Mode = .estimated) -> VehicleMarkerStaleness {
        VehicleMarkerStaleness(estimate: TripMapFocusFixture.estimate(at: here, fixAge: age, mode: mode))
    }

    @Test func `No estimate, or a raw one, looks as it always has`() {
        #expect(VehicleMarkerStaleness(estimate: nil) == .live)
        #expect(staleness(age: 100, mode: .raw(.offShape)) == .live)
    }

    @Test func `A fresh estimate is live`() {
        #expect(staleness(age: 0) == .live)
        #expect(staleness(age: 44) == .live)
    }

    @Test func `An aging estimate grows its halo and slows its pulse toward the horizon`() {
        let early = staleness(age: 50), late = staleness(age: 110)
        #expect(early.haloDiameter > 0)
        #expect(late.haloDiameter > early.haloDiameter)
        #expect(late.haloDiameter <= VehicleMarkerStaleness.maximumHaloDiameter)
        #expect(late.pulseDelay > early.pulseDelay)
        #expect(early.alpha == 1)
        #expect(early.showsHeading)
    }

    @Test func `A frozen estimate stops pulsing, fades and drops its heading`() {
        let frozen = staleness(age: 300, mode: .frozen)
        #expect(frozen == .frozen)
        #expect(frozen.alpha == 0.6)
        #expect(frozen.pulseDelay == .infinity)
        #expect(!frozen.showsHeading)
        #expect(frozen.haloDiameter == 0)
    }

    // MARK: - The marker view

    private func markerView() throws -> PulsingVehicleAnnotationView {
        let annotation = VehicleAnnotation(tripStatus: try TripMapFocusFixture.vehicle())
        return PulsingVehicleAnnotationView(annotation: annotation, reuseIdentifier: nil)
    }

    @Test func `An estimate points the marker along the shape`() throws {
        let view = try markerView()
        // Compass 0° (north) is OBA 90°, which the view draws as a −90° rotation.
        view.applyEstimate(TripMapFocusFixture.estimate(at: here, bearing: 0))
        let angle = atan2(view.headingImageView.transform.b, view.headingImageView.transform.a)
        expectClose(Double(angle), -Double.pi / 2, within: 0.0001)
        #expect(!view.headingImageView.isHidden)
    }

    @Test func `A frozen estimate fades the marker and hides its heading`() throws {
        let view = try markerView()
        view.applyEstimate(TripMapFocusFixture.estimate(at: here, fixAge: 300, mode: .frozen))
        #expect(view.alpha == 0.6)
        #expect(view.headingImageView.isHidden)
    }

    @Test func `Clearing the estimate restores the marker`() throws {
        let view = try markerView()
        view.applyEstimate(TripMapFocusFixture.estimate(at: here, fixAge: 300, mode: .frozen))
        view.applyEstimate(nil)
        #expect(view.alpha == 1)
        #expect(view.uncertaintyHaloDiameter == 0)
    }

    @Test func `An aging estimate draws a halo`() throws {
        let view = try markerView()
        view.applyEstimate(TripMapFocusFixture.estimate(at: here, fixAge: 90))
        #expect(view.uncertaintyHaloDiameter > 0)
    }
}
