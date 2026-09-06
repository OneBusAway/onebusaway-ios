//
//  TripPlannerEndpointsTests.swift
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

/// Pins the stop ↔ map-item ↔ OTPKit `Location` mapping used to prefill the
/// trip planner from a stop page — without loading `MapViewController.view`.
@MainActor
@Suite(.serialized)
final class TripPlannerEndpointsTests: OBATestCase {

    @Test func `Stop maps to MKMapItem with stop title and coordinate`() throws {
        let stop = try #require(Fixtures.loadSomeStops().first)
        let mapItem = TripPlannerEndpoints.mapItem(from: stop)

        #expect(mapItem.name == stop.title)
        #expect(mapItem.placemark.coordinate.latitude == stop.coordinate.latitude)
        #expect(mapItem.placemark.coordinate.longitude == stop.coordinate.longitude)
    }

    @Test func `MKMapItem maps to OTPKit Location with name and coordinates`() {
        let coordinate = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = "Pike Place Market"

        let location = TripPlannerEndpoints.location(from: mapItem)

        #expect(location.title == "Pike Place Market")
        #expect(location.latitude == coordinate.latitude)
        #expect(location.longitude == coordinate.longitude)
    }

    @Test func `Current CLLocation maps to Current Location titled OTP Location`() {
        let current = CLLocation(latitude: 47.61, longitude: -122.33)
        let location = TripPlannerEndpoints.location(fromCurrentLocation: current)

        #expect(location.title == "Current Location")
        #expect(location.subTitle == "Your current location")
        #expect(location.latitude == 47.61)
        #expect(location.longitude == -122.33)
    }

    @Test func `Explicit origin wins over current location`() {
        let stopItem = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)))
        stopItem.name = "Stop Origin"
        let current = CLLocation(latitude: 47.61, longitude: -122.33)

        let origin = TripPlannerEndpoints.origin(explicit: stopItem, currentLocation: current)

        #expect(origin?.title == "Stop Origin")
        #expect(origin?.latitude == 47.6)
        #expect(origin?.longitude == -122.3)
    }

    @Test func `Nil explicit origin falls back to current location`() {
        let current = CLLocation(latitude: 47.61, longitude: -122.33)

        let origin = TripPlannerEndpoints.origin(explicit: nil, currentLocation: current)

        #expect(origin?.title == "Current Location")
        #expect(origin?.latitude == 47.61)
        #expect(origin?.longitude == -122.33)
    }

    @Test func `Destination maps from map item when present`() {
        let destinationItem = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 47.62, longitude: -122.35)))
        destinationItem.name = "Stop Destination"

        let destination = TripPlannerEndpoints.destination(from: destinationItem)

        #expect(destination?.title == "Stop Destination")
        #expect(destination?.latitude == 47.62)
        #expect(destination?.longitude == -122.35)
        #expect(TripPlannerEndpoints.destination(from: nil) == nil)
    }
}
