//
//  TripPlannerMapDelegateTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import ObjectiveC
import Testing
import UIKit
import OBAKitCore
import OTPKit
@testable import OBAKit

/// #1449: route mode's map is delegated to OTPKit's `MKMapViewAdapter`, which
/// returns `nil` for `MKUserLocation`, so the rider got the plain system dot
/// instead of the heading cone the main map draws.
@MainActor
@Suite(.serialized)
final class TripPlannerMapDelegateTests {

    private let locationManager: MockAuthorizedLocationManager
    private let locationService: LocationService
    private let mapView = MKMapView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
    private let adapter: MKMapViewAdapter

    init() {
        locationManager = MockAuthorizedLocationManager(
            updateLocation: TestData.mockSeattleLocation,
            updateHeading: TestData.mockHeading
        )
        let userDefaults = UserDefaults(suiteName: "TripPlannerMapDelegateTests-\(UUID().uuidString)")!
        locationService = LocationService(userDefaults: userDefaults, locationManager: locationManager)
        adapter = MKMapViewAdapter(mapView: mapView)
    }

    private func makeSubject(showsHeading: Bool = true) -> TripPlannerMapDelegate {
        let subject = TripPlannerMapDelegate(
            forwardingTo: adapter,
            locationService: locationService,
            showsHeading: showsHeading
        )
        subject.attach(to: mapView)
        return subject
    }

    @Test func attachReplacesTheAdapterAsDelegate() {
        let subject = makeSubject()
        #expect(mapView.delegate === subject)
    }

    @Test func userLocationGetsTheHeadingConeView() throws {
        let subject = makeSubject()

        let view = try #require(subject.mapView(mapView, viewFor: mapView.userLocation) as? PulsingAnnotationView)
        locationService.startUpdatingHeading()

        #expect(view.headingImage != nil)
        #expect(view.headingImageView.isHidden == false)
        #expect(view.headingImageView.transform != .identity)
    }

    @Test func headingSettingOffHidesTheCone() throws {
        let subject = makeSubject(showsHeading: false)

        let view = try #require(subject.mapView(mapView, viewFor: mapView.userLocation) as? PulsingAnnotationView)

        #expect(view.headingImageView.isHidden)
    }

    /// Mirrors the main map: reduced accuracy keeps the system view, which draws
    /// the imprecise-area circle that the pulsing dot can't.
    @Test func reducedAccuracyKeepsTheSystemView() {
        locationManager.overrideAccuracyAuthorization = .reducedAccuracy
        let subject = makeSubject()

        #expect(subject.mapView(mapView, viewFor: mapView.userLocation) == nil)
    }

    @Test func otherAnnotationsStillComeFromTheAdapter() throws {
        let subject = makeSubject()
        adapter.addAnnotation(
            coordinate: TestData.mockSeattleLocation.coordinate,
            title: "Destination",
            subtitle: nil,
            identifier: "destination",
            type: .destination
        )
        let annotation = try #require(mapView.annotations.first { !($0 is MKUserLocation) })

        #expect(subject.mapView(mapView, viewFor: annotation) is MKMarkerAnnotationView)
    }

    /// `MKMapView` only calls optional delegate methods its delegate responds
    /// to, so a method OTPKit starts implementing that this class doesn't
    /// forward would silently stop working in route mode.
    @Test func forwardsEveryDelegateMethodTheAdapterImplements() throws {
        let subject = makeSubject()
        let mapViewDelegate = try #require(objc_getProtocol("MKMapViewDelegate"))

        var count: UInt32 = 0
        let methods = try #require(protocol_copyMethodDescriptionList(mapViewDelegate, false, true, &count))
        defer { free(methods) }

        let implementedByAdapter = (0..<Int(count))
            .compactMap { methods[$0].name }
            .filter { adapter.responds(to: $0) }

        #expect(!implementedByAdapter.isEmpty)
        for selector in implementedByAdapter {
            #expect(subject.responds(to: selector), "Not forwarded: \(NSStringFromSelector(selector))")
        }
    }
}
