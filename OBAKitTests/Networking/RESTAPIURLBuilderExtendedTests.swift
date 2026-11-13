//
//  RESTAPIURLBuilderExtendedTests.swift
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
@testable import OBAKitCore

/// Extended tests for `RESTAPIURLBuilder` query parameter escaping,
/// path component sanitization, and region URL building edge cases.
@Suite(.serialized)
final class RESTAPIURLBuilderExtendedTests {

    private let builder = RESTAPIURLBuilder(
        baseURL: URL(string: "https://api.example.com")!,
        defaultQueryItems: [URLQueryItem(name: "key", value: "TEST_KEY")],
        surveyBaseURL: URL(string: "https://surveys.example.com")!
    )

    private func queryValue(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }

    @Test func `getShape encodes special characters in shape ID`() {
        let shapeID = "1_shape/variant:1"
        let url = builder.getShape(id: shapeID)

        #expect(queryValue(url, "key") == "TEST_KEY")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let percentEncodedPath = components?.percentEncodedPath ?? ""
        #expect(percentEncodedPath == "/api/where/shape/1_shape%2Fvariant:1.json")
    }

    @Test func `getStopsForLocation produces non-empty query parameters`() {
        let coord = CLLocationCoordinate2D(latitude: 47.6097, longitude: -122.3331)
        let region = MKCoordinateRegion(center: coord, latitudinalMeters: 500, longitudinalMeters: 500)

        let url = builder.getStops(region: region)
        #expect(queryValue(url, "key") == "TEST_KEY")
        #expect(queryValue(url, "lat") == "47.6097")
        #expect(queryValue(url, "lon") == "-122.3331")
        #expect(queryValue(url, "latSpan") == "\(region.span.latitudeDelta)")
        #expect(queryValue(url, "lonSpan") == "\(region.span.longitudeDelta)")
    }

    @Test func `getTrip includes default key and tripID in path`() {
        let url = builder.getTrip(tripID: "1_4321098", vehicleID: nil, serviceDate: nil)
        #expect(url.path == "/api/where/trip-details/1_4321098.json")
        #expect(queryValue(url, "key") == "TEST_KEY")
    }

    @Test func `getTripArrivalDepartureAtStop includes stopID tripID serviceDate and stopSequence`() {
        let url = builder.getTripArrivalDepartureAtStop(
            stopID: "1_10020",
            tripID: "1_998877",
            serviceDate: Date(timeIntervalSince1970: 1_700_000_000),
            vehicleID: nil,
            stopSequence: 3
        )
        #expect(url.path == "/api/where/arrival-and-departure-for-stop/1_10020.json")
        #expect(queryValue(url, "tripId") == "1_998877")
        #expect(queryValue(url, "serviceDate") == "1700000000000")
        #expect(queryValue(url, "stopSequence") == "3")
        #expect(queryValue(url, "key") == "TEST_KEY")
    }
}
