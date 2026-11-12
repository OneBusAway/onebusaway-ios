//
//  TripPlannerEndpointsExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import MapKit
import Testing
import OTPKit
@testable import OBAKit
@testable import OBAKitCore

/// Extended tests for `TripPlannerEndpoints` fallback names, coordinate bounds,
/// and nil origin/destination edge cases.
@MainActor
@Suite(.serialized)
final class TripPlannerEndpointsExtendedTests: OBATestCase {

    @Test func `location from map item with nil name uses fallback title`() {
        let coord = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coord))
        mapItem.name = nil

        let location = TripPlannerEndpoints.location(from: mapItem)
        #expect(location.title == "Destination")
        #expect(location.latitude == 47.6062)
        #expect(location.longitude == -122.3321)
    }

    @Test func `location from map item with empty name preserves empty string`() {
        let coord = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coord))
        mapItem.name = ""

        let location = TripPlannerEndpoints.location(from: mapItem)
        #expect(location.title == "")
    }

    @Test func `origin with nil explicit and nil currentLocation returns nil`() {
        let origin = TripPlannerEndpoints.origin(explicit: nil, currentLocation: nil)
        #expect(origin == nil)
    }

    @Test func `destination with nil mapItem returns nil`() {
        let destination = TripPlannerEndpoints.destination(from: nil)
        #expect(destination == nil)
    }

    @Test func `mapItem from Stop preserves exact coordinates and title`() throws {
        let stops = try Fixtures.loadSomeStops()
        for stop in stops.prefix(3) {
            let item = TripPlannerEndpoints.mapItem(from: stop)
            #expect(item.name == stop.title)
            #expect(item.placemark.coordinate.latitude == stop.coordinate.latitude)
            #expect(item.placemark.coordinate.longitude == stop.coordinate.longitude)
        }
    }

    @Test func `origin explicit map item takes precedence even with current location`() {
        let coord1 = CLLocationCoordinate2D(latitude: 47.65, longitude: -122.30)
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coord1))
        mapItem.name = "University of Washington"

        let currentLoc = CLLocation(latitude: 47.60, longitude: -122.33)

        let origin = TripPlannerEndpoints.origin(explicit: mapItem, currentLocation: currentLoc)
        #expect(origin?.title == "University of Washington")
        #expect(origin?.latitude == 47.65)
        #expect(origin?.longitude == -122.30)
    }
}
