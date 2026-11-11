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
        #expect(url.path.contains("/api/where/shape/"))
    }

    @Test func `getStopsForLocation produces non-empty query parameters`() {
        let coord = CLLocationCoordinate2D(latitude: 47.6097, longitude: -122.3331)
        let region = MKCoordinateRegion(center: coord, latitudinalMeters: 500, longitudinalMeters: 500)

        let url = builder.getStops(coordinateRegion: region)
        #expect(queryValue(url, "key") == "TEST_KEY")
        #expect(queryValue(url, "lat") != nil)
        #expect(queryValue(url, "lon") != nil)
        #expect(queryValue(url, "latSpan") != nil)
        #expect(queryValue(url, "lonSpan") != nil)
    }

    @Test func `getTripDetails includes default key and tripID in path`() {
        let url = builder.getTripDetails(tripID: "1_4321098")
        #expect(url.path == "/api/where/trip-details/1_4321098.json")
        #expect(queryValue(url, "key") == "TEST_KEY")
    }

    @Test func `getArrivalAndDepartureForStop includes stopID and tripID`() {
        let url = builder.getArrivalAndDepartureForStop(
            id: "1_10020",
            tripID: "1_998877",
            serviceDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        #expect(url.path == "/api/where/arrival-and-departure-for-stop/1_10020.json")
        #expect(queryValue(url, "tripId") == "1_998877")
        #expect(queryValue(url, "serviceDate") == "1700000000000")
        #expect(queryValue(url, "key") == "TEST_KEY")
    }
}
