//
//  MapPanelHeadingIndicatorTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import SwiftUI
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// #1890: the map panel drew MapKit's puck, so the rider got a system-blue
/// cone instead of the app's own heading indicator in its accent color.
@MainActor
@Suite(.serialized)
struct MapPanelHeadingIndicatorTests {

    // MARK: - Which puck

    @Test func `Show Heading off keeps the panel's dot`() {
        #expect(!MapPanelHeadingIndicator.usesSystemPuck(showsHeading: false, isReducedAccuracy: false))
        #expect(!MapPanelHeadingIndicator.usesSystemPuck(showsHeading: false, isReducedAccuracy: true))
    }

    @Test func `Show Heading on with full accuracy draws the panel's own dot and cone`() {
        #expect(!MapPanelHeadingIndicator.usesSystemPuck(showsHeading: true, isReducedAccuracy: false))
    }

    /// Mirrors the UIKit map, which keeps `MKUserLocationView` for its
    /// imprecise-area circle.
    @Test func `Reduced accuracy with Show Heading on keeps MapKit's puck`() {
        #expect(MapPanelHeadingIndicator.usesSystemPuck(showsHeading: true, isReducedAccuracy: true))
    }

    // MARK: - Cone visibility

    @Test func `Show Heading off draws no cone`() {
        #expect(MapPanelHeadingIndicator.coneRotation(showsHeading: false, direction: 45, cameraHeading: 0) == nil)
    }

    @Test func `No heading draws no cone`() {
        #expect(MapPanelHeadingIndicator.coneRotation(showsHeading: true, direction: nil, cameraHeading: 0) == nil)
    }

    @Test func `Show Heading on with a heading draws the cone`() {
        #expect(MapPanelHeadingIndicator.coneRotation(showsHeading: true, direction: 45, cameraHeading: 0) == .degrees(315))
    }

    // MARK: - Cone rotation

    /// The asset points east, so north needs a quarter turn back.
    @Test func `Facing north on a north-up map turns the east-pointing cone a quarter turn back`() {
        #expect(MapPanelHeadingIndicator.coneRotation(direction: 0, cameraHeading: 0) == .degrees(270))
    }

    @Test func `Facing east on a north-up map leaves the cone as drawn`() {
        #expect(MapPanelHeadingIndicator.coneRotation(direction: 90, cameraHeading: 0) == .degrees(0))
    }

    @Test func `Facing south on a north-up map points the cone down`() {
        #expect(MapPanelHeadingIndicator.coneRotation(direction: 180, cameraHeading: 0) == .degrees(90))
    }

    /// Annotations stay upright as the map turns, so the cone has to make up
    /// the difference.
    @Test func `A rotated map takes the camera heading off the cone`() {
        // Facing east with the map turned east-up: the rider faces screen-up.
        #expect(MapPanelHeadingIndicator.coneRotation(direction: 90, cameraHeading: 90) == .degrees(270))
        // Facing north with the map turned east-up: the rider faces screen-left.
        #expect(MapPanelHeadingIndicator.coneRotation(direction: 0, cameraHeading: 90) == .degrees(180))
    }

    @Test func `Rotations stay within one turn`() {
        #expect(MapPanelHeadingIndicator.coneRotation(direction: 359, cameraHeading: 0) == .degrees(269))
        #expect(MapPanelHeadingIndicator.coneRotation(direction: 10, cameraHeading: 350) == .degrees(290))
        #expect(MapPanelHeadingIndicator.coneRotation(direction: 90, cameraHeading: 360) == .degrees(0))
    }

    // MARK: - Heading direction

    @Test func `True heading is used when it's known`() {
        let heading = OBAMockHeading(magneticHeading: 40, trueHeading: 55)
        #expect(MapPanelHeadingIndicator.direction(of: heading) == 55)
    }

    /// True heading needs a location fix and reads negative until one arrives.
    @Test func `Magnetic heading stands in until true heading is known`() {
        let heading = OBAMockHeading(magneticHeading: 40, trueHeading: -1)
        #expect(MapPanelHeadingIndicator.direction(of: heading) == 40)
    }

    @Test func `An invalid reading has no direction`() {
        let heading = OBAMockHeading(magneticHeading: 40, trueHeading: 55, headingAccuracy: -1)
        #expect(MapPanelHeadingIndicator.direction(of: heading) == nil)
    }

    @Test func `No heading has no direction`() {
        #expect(MapPanelHeadingIndicator.direction(of: nil) == nil)
    }

    // MARK: - Observer

    private func makeLocationService(
        heading: CLHeading = TestData.mockHeading
    ) -> (LocationService, MockAuthorizedLocationManager) {
        let locationManager = MockAuthorizedLocationManager(
            updateLocation: TestData.mockSeattleLocation,
            updateHeading: heading
        )
        let userDefaults = UserDefaults(suiteName: "MapPanelHeadingIndicatorTests-\(UUID().uuidString)")!
        return (LocationService(userDefaults: userDefaults, locationManager: locationManager), locationManager)
    }

    @Test func `The observer starts with no direction before heading updates start`() {
        let (locationService, _) = makeLocationService()
        let observer = MapPanelHeadingObserver(locationService: locationService)

        #expect(observer.direction == nil)
        #expect(!observer.isReducedAccuracy)
    }

    @Test func `The observer picks up a heading the service already has`() {
        let (locationService, _) = makeLocationService()
        locationService.startUpdatingHeading()

        let observer = MapPanelHeadingObserver(locationService: locationService)
        #expect(observer.direction == 45)
    }

    @Test func `The observer follows heading updates`() {
        let (locationService, locationManager) = makeLocationService()
        let observer = MapPanelHeadingObserver(locationService: locationService)

        locationService.startUpdatingHeading()
        #expect(observer.direction == 45)

        locationManager.heading = OBAMockHeading(magneticHeading: 200, trueHeading: 210)
        #expect(observer.direction == 210)

        locationManager.heading = OBAMockHeading(magneticHeading: 200, trueHeading: 210, headingAccuracy: -1)
        #expect(observer.direction == nil)
    }

    @Test func `The observer follows accuracy changes`() {
        let (locationService, locationManager) = makeLocationService()
        let observer = MapPanelHeadingObserver(locationService: locationService)

        locationManager.overrideAccuracyAuthorization = .reducedAccuracy
        locationService.locationManagerDidChangeAuthorization(CLLocationManager())
        #expect(observer.isReducedAccuracy)

        locationManager.overrideAccuracyAuthorization = .fullAccuracy
        locationService.locationManagerDidChangeAuthorization(CLLocationManager())
        #expect(!observer.isReducedAccuracy)
    }

    @Test func `The observer starts reduced when the service already is`() {
        let (locationService, locationManager) = makeLocationService()
        locationManager.overrideAccuracyAuthorization = .reducedAccuracy

        #expect(MapPanelHeadingObserver(locationService: locationService).isReducedAccuracy)
    }

    /// The delegate table is weak; the panel's observer must not outlive it.
    @Test func `The service doesn't keep the observer alive`() {
        let (locationService, _) = makeLocationService()
        weak var weakObserver: MapPanelHeadingObserver?
        do {
            let observer = MapPanelHeadingObserver(locationService: locationService)
            weakObserver = observer
        }
        #expect(weakObserver == nil)
    }
}
