//
//  PulsingAnnotationViewTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import MapKit
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class PulsingAnnotationViewTests {

    // MARK: - PulsingAnnotationView Reduce Motion

    @Test func `PulsingAnnotationView enables pulse animations when Reduce Motion is off`() {
        let view = PulsingAnnotationView(annotation: nil, reuseIdentifier: "test")
        view.isReduceMotionEnabled = false

        #expect(view.hasPulseAnimation)
        #expect(view.colorDotLayer.animation(forKey: "pulse") != nil)
        #expect(view.colorHaloLayer.animation(forKey: "pulse") != nil)
    }

    @Test func `PulsingAnnotationView disables pulse animations when Reduce Motion is on`() {
        let view = PulsingAnnotationView(annotation: nil, reuseIdentifier: "test")
        view.isReduceMotionEnabled = true

        #expect(!view.hasPulseAnimation)
        #expect(view.colorDotLayer.animation(forKey: "pulse") == nil)
        #expect(view.colorHaloLayer.animation(forKey: "pulse") == nil)
        #expect(view.colorHaloLayer.opacity == 0)
    }

    @Test func `PulsingAnnotationView dynamically updates on reduceMotionStatusDidChangeNotification`() {
        let view = PulsingAnnotationView(annotation: nil, reuseIdentifier: "test")
        var reduceMotionState = false
        view.reduceMotionProvider = { reduceMotionState }
        view.rebuildLayers()

        #expect(view.hasPulseAnimation)

        // Simulate user enabling Reduce Motion in iOS Settings
        reduceMotionState = true
        NotificationCenter.default.post(
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )

        #expect(view.isReduceMotionEnabled)
        #expect(!view.hasPulseAnimation)
        #expect(view.colorDotLayer.animation(forKey: "pulse") == nil)
        #expect(view.colorHaloLayer.animation(forKey: "pulse") == nil)

        // Simulate user disabling Reduce Motion in iOS Settings
        reduceMotionState = false
        NotificationCenter.default.post(
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )

        #expect(!view.isReduceMotionEnabled)
        #expect(view.hasPulseAnimation)
        #expect(view.colorDotLayer.animation(forKey: "pulse") != nil)
        #expect(view.colorHaloLayer.animation(forKey: "pulse") != nil)
    }

    @Test func `PulsingAnnotationView popIn respects Reduce Motion`() {
        let view = PulsingAnnotationView(annotation: nil, reuseIdentifier: "test")
        view.isReduceMotionEnabled = true
        view.popIn()
        #expect(view.layer.animation(forKey: "popIn") == nil)

        view.isReduceMotionEnabled = false
        view.popIn()
        #expect(view.layer.animation(forKey: "popIn") != nil)
    }

    @Test func `PulsingAnnotationView willMoveToSuperview respects Reduce Motion`() {
        let view = PulsingAnnotationView(annotation: nil, reuseIdentifier: "test")
        let superview = UIView()

        view.isReduceMotionEnabled = true
        view.willMove(toSuperview: superview)
        #expect(view.layer.animation(forKey: "popIn") == nil)
        #expect(!view.hasPulseAnimation)

        view.isReduceMotionEnabled = false
        view.willMove(toSuperview: superview)
        #expect(view.layer.animation(forKey: "popIn") != nil)
        #expect(view.hasPulseAnimation)
    }

    // MARK: - PulsingVehicleAnnotationView Reduce Motion

    @Test func `PulsingVehicleAnnotationView real-time vehicle pulses when Reduce Motion is off`() {
        let view = PulsingVehicleAnnotationView(annotation: nil, reuseIdentifier: "test")
        view.isRealTime = true
        view.isReduceMotionEnabled = false

        #expect(view.hasPulseAnimation)
        #expect(view.colorDotLayer.animation(forKey: "pulse") != nil)
        #expect(view.colorHaloLayer.animation(forKey: "pulse") != nil)
    }

    @Test func `PulsingVehicleAnnotationView real-time vehicle disables pulsing when Reduce Motion is on`() {
        let view = PulsingVehicleAnnotationView(annotation: nil, reuseIdentifier: "test")
        view.isRealTime = true
        view.isReduceMotionEnabled = true

        #expect(!view.hasPulseAnimation)
        #expect(view.colorDotLayer.animation(forKey: "pulse") == nil)
        #expect(view.colorHaloLayer.animation(forKey: "pulse") == nil)
    }

    @Test func `PulsingVehicleAnnotationView scheduled vehicle never pulses regardless of Reduce Motion`() {
        let view = PulsingVehicleAnnotationView(annotation: nil, reuseIdentifier: "test")
        view.isRealTime = false

        view.isReduceMotionEnabled = false
        #expect(!view.hasPulseAnimation)

        view.isReduceMotionEnabled = true
        #expect(!view.hasPulseAnimation)
    }

    @Test func `PulsingVehicleAnnotationView preserves selection and interaction under Reduce Motion`() {
        let view = PulsingVehicleAnnotationView(annotation: nil, reuseIdentifier: "test")
        view.isReduceMotionEnabled = true

        #expect(view.canShowCallout)
        #expect(!view.isUserInteractionEnabled)

        view.isSelectable = true
        #expect(view.isUserInteractionEnabled)

        view.isSelectable = false
        #expect(!view.isUserInteractionEnabled)
    }

    @Test func `PulsingVehicleAnnotationView preserves non-animated styling under Reduce Motion`() throws {
        let vehicle = try TripMapFocusFixture.vehicle()
        let annotation = VehicleAnnotation(tripStatus: vehicle)
        let view = PulsingVehicleAnnotationView(annotation: annotation, reuseIdentifier: "test")
        view.isReduceMotionEnabled = true

        // Route color / styling
        let brandColor = UIColor.systemPurple
        view.realTimeAnnotationColor = brandColor
        #expect(view.annotationColor == brandColor)
        #expect(view.headingImageView.tintColor == brandColor)

        // Route type icon
        view.routeType = .bus
        #expect(view.image != nil)

        // Heading transform
        #expect(!view.headingImageView.isHidden)

        // Uncertainty halo from staleness estimate is preserved
        let estimate = TripMapFocusFixture.estimate(at: CLLocationCoordinate2D(latitude: 47, longitude: -122), fixAge: 90)
        view.applyEstimate(estimate)
        #expect(view.uncertaintyHaloDiameter > 0)
        #expect(!view.hasPulseAnimation)
    }

    @Test func `PulsingVehicleAnnotationView dynamic Reduce Motion toggle preserves styling`() {
        let view = PulsingVehicleAnnotationView(annotation: nil, reuseIdentifier: "test")
        view.isRealTime = true
        view.realTimeAnnotationColor = .systemTeal
        var motionState = false
        view.reduceMotionProvider = { motionState }
        view.rebuildLayers()

        #expect(view.hasPulseAnimation)
        #expect(view.annotationColor == .systemTeal)

        motionState = true
        NotificationCenter.default.post(
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )

        #expect(!view.hasPulseAnimation)
        #expect(view.annotationColor == .systemTeal)

        motionState = false
        NotificationCenter.default.post(
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )

        #expect(view.hasPulseAnimation)
        #expect(view.annotationColor == .systemTeal)
    }
}
