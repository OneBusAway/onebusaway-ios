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

    @Test func `Attach replaces the adapter as the map delegate`() {
        let subject = makeSubject()
        #expect(mapView.delegate === subject)
    }

    @Test func `The user location gets the heading cone view`() throws {
        let subject = makeSubject()

        let view = try #require(subject.mapView(mapView, viewFor: mapView.userLocation) as? PulsingAnnotationView)
        locationService.startUpdatingHeading()

        #expect(view.headingImage != nil)
        #expect(view.headingImageView.isHidden == false)
        #expect(view.headingImageView.transform != .identity)
    }

    @Test func `Turning the heading setting off hides the cone`() throws {
        let subject = makeSubject(showsHeading: false)

        let view = try #require(subject.mapView(mapView, viewFor: mapView.userLocation) as? PulsingAnnotationView)

        #expect(view.headingImageView.isHidden)
    }

    /// Mirrors the main map: reduced accuracy keeps the system view, which draws
    /// the imprecise-area circle that the pulsing dot can't.
    @Test func `Reduced accuracy keeps the system view`() {
        locationManager.overrideAccuracyAuthorization = .reducedAccuracy
        let subject = makeSubject()

        #expect(subject.mapView(mapView, viewFor: mapView.userLocation) == nil)
    }

    // MARK: - Replacing a stale user location view

    /// Records every `showsUserLocation` write, and can report that MapKit is
    /// already showing a user location view of its own — which a headless map
    /// never does, since it has no location to show.
    private final class UserLocationSpyMapView: MKMapView {
        var showsUserLocationWrites: [Bool] = []
        var existingUserLocationView: MKAnnotationView?

        override var showsUserLocation: Bool {
            didSet { showsUserLocationWrites.append(showsUserLocation) }
        }

        override func view(for annotation: MKAnnotation) -> MKAnnotationView? {
            annotation is MKUserLocation ? existingUserLocationView : super.view(for: annotation)
        }
    }

    private func makeSpySubject(showsUserLocation: Bool, existingView: MKAnnotationView? = nil) -> (TripPlannerMapDelegate, UserLocationSpyMapView) {
        let spy = UserLocationSpyMapView(frame: mapView.frame)
        spy.showsUserLocation = showsUserLocation
        spy.existingUserLocationView = existingView
        spy.showsUserLocationWrites = []

        let subject = TripPlannerMapDelegate(
            forwardingTo: MKMapViewAdapter(mapView: spy),
            locationService: locationService,
            showsHeading: true
        )
        subject.attach(to: spy)
        return (subject, spy)
    }

    /// The planner's map outlives each session and goes undelegated in between,
    /// so it can come back holding the plain system dot — and MapKit won't ask
    /// for a user location view it already has.
    @Test func `Attach replaces a system user location view the map is already showing`() {
        let (_, spy) = makeSpySubject(showsUserLocation: true, existingView: MKAnnotationView())
        #expect(spy.showsUserLocationWrites == [false, true])
    }

    @Test func `Attach leaves an existing pulsing view in place`() {
        let (_, spy) = makeSpySubject(showsUserLocation: true, existingView: PulsingAnnotationView(annotation: nil, reuseIdentifier: nil))
        #expect(spy.showsUserLocationWrites.isEmpty)
    }

    @Test func `Attach keeps the system view under reduced accuracy`() {
        locationManager.overrideAccuracyAuthorization = .reducedAccuracy
        let (_, spy) = makeSpySubject(showsUserLocation: true, existingView: MKAnnotationView())
        #expect(spy.showsUserLocationWrites.isEmpty)
    }

    /// Which view the user location gets depends on accuracy, so a change has
    /// to make MapKit ask again.
    @Test func `An accuracy change refreshes the user location view`() {
        let (subject, spy) = makeSpySubject(showsUserLocation: true)

        subject.locationService(locationService, accuracyAuthorizationChanged: .reducedAccuracy)

        #expect(spy.showsUserLocationWrites == [false, true])
    }

    @Test func `An accuracy change doesn't turn on a hidden user location`() {
        let (subject, spy) = makeSpySubject(showsUserLocation: false)

        subject.locationService(locationService, accuracyAuthorizationChanged: .fullAccuracy)

        #expect(spy.showsUserLocationWrites.isEmpty)
        #expect(spy.showsUserLocation == false)
    }

    @Test func `Other annotations still come from the adapter`() throws {
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
    @Test func `Forwards every delegate method the adapter implements`() throws {
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
