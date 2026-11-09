//
//  URLSchemeRouterDeepLinkRoutingTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
@testable import OBAKitCore

/// Tests for `URLSchemeRouter` deep link parsing, boundary validation, and URL generation.
///
/// Exercises view-stop, add-region, and view-rentals host decoding with extreme geographic
/// coordinates, malformed URL structures, percent-encoded query items, and schema validation.
@Suite(.serialized)
struct URLSchemeRouterDeepLinkRoutingTests {

    private let router = URLSchemeRouter(scheme: "onebusaway")

    // MARK: - View Rentals Boundary Coordinates

    @Test func `decodeURLType viewRentals parses valid coordinates across hemispheres`() {
        let testCases: [(lat: Double, lon: Double)] = [
            (47.6062, -122.3321), // Seattle
            (-33.8688, 151.2093), // Sydney
            (51.5074, -0.1278),   // London
            (0.0, 0.0),           // Equator / Prime Meridian
            (90.0, 0.0),          // North Pole
            (-90.0, 0.0),         // South Pole
            (0.0, 180.0),         // Antimeridian East
            (0.0, -180.0)         // Antimeridian West
        ]

        for (lat, lon) in testCases {
            let encoded = router.encodeViewRentals(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
            guard let decoded = router.decodeURLType(from: encoded) else {
                Issue.record("Failed to decode rentals URL for (\(lat), \(lon))")
                continue
            }

            guard case let .viewRentals(coordinate) = decoded else {
                Issue.record("Expected .viewRentals type")
                continue
            }

            #expect(abs(coordinate.latitude - lat) < 0.0001)
            #expect(abs(coordinate.longitude - lon) < 0.0001)
        }
    }

    @Test func `decodeURLType viewRentals rejects out of bounds latitude and longitude`() {
        let invalidUrls = [
            "onebusaway://rentals?lat=90.0001&lon=0.0",
            "onebusaway://rentals?lat=-90.0001&lon=0.0",
            "onebusaway://rentals?lat=0.0&lon=180.0001",
            "onebusaway://rentals?lat=0.0&lon=-180.0001",
            "onebusaway://rentals?lat=NaN&lon=0.0",
            "onebusaway://rentals?lat=0.0&lon=Infinity",
            "onebusaway://rentals?lat=&lon=",
            "onebusaway://rentals?lat=abc&lon=xyz",
            "onebusaway://rentals?lat=47.60", // Missing lon
            "onebusaway://rentals?lon=-122.33" // Missing lat
        ]

        for urlString in invalidUrls {
            let url = URL(string: urlString)!
            #expect(router.decodeURLType(from: url) == nil)
        }
    }

    // MARK: - View Stop Deep Links

    @Test func `encodeViewStop crafts compliant extension scheme URL`() {
        let url = router.encodeViewStop(stopID: "1_10020", regionID: 1)
        #expect(url.scheme == "onebusaway")
        #expect(url.host == "view-stop")
        #expect(url.absoluteString.contains("stopID=1_10020"))
        #expect(url.absoluteString.contains("regionID=1"))
    }

    @Test func `decodeViewStop decodes stopID and regionID correctly`() {
        let url = URL(string: "onebusaway://view-stop?stopID=29_5432&regionID=2")!
        let decoded = router.decodeURLType(from: url)

        guard case let .viewStop(stopData) = decoded else {
            Issue.record("Expected .viewStop")
            return
        }

        #expect(stopData.stopID == "29_5432")
        #expect(stopData.regionID == 2)
    }

    @Test func `decodeViewStop returns nil when regionID is non-integer or missing`() {
        let invalidRegionUrls = [
            "onebusaway://view-stop?stopID=1_10020",
            "onebusaway://view-stop?stopID=1_10020&regionID=",
            "onebusaway://view-stop?stopID=1_10020&regionID=not_an_int",
            "onebusaway://view-stop?regionID=1" // Missing stopID
        ]

        for urlString in invalidRegionUrls {
            let url = URL(string: urlString)!
            #expect(router.decodeURLType(from: url) == nil)
        }
    }

    // MARK: - Add Region Deep Links

    @Test func `decodeAddRegion decodes required fields and optional sidecar parameters`() {
        let urlString = "onebusaway://add-region?name=Custom%20Transit&oba-url=https%3A%2F%2Fapi.example.com%2Foba&region-id=42&otp-url=https%3A%2F%2Fotp.example.com&otp-graphql-url=https%3A%2F%2Fotp.example.com%2Fgraphql&otp-graphql-bikeshare=true&sidecar-url=https%3A%2F%2Fsidecar.example.com&umami-url=https%3A%2F%2Fanalytics.example.com&umami-id=project-123"
        let url = URL(string: urlString)!
        let decoded = router.decodeURLType(from: url)

        guard case let .addRegion(dataOpt) = decoded, let data = dataOpt else {
            Issue.record("Expected non-nil addRegion data")
            return
        }

        #expect(data.name == "Custom Transit")
        #expect(data.regionID == 42)
        #expect(data.obaURL == URL(string: "https://api.example.com/oba")!)
        #expect(data.otpURL == URL(string: "https://otp.example.com")!)
        #expect(data.otpGraphQLURL == URL(string: "https://otp.example.com/graphql")!)
        #expect(data.supportsOTPGraphQLBikeshare == true)
        #expect(data.sidecarURL == URL(string: "https://sidecar.example.com")!)
        #expect(data.umamiURL == URL(string: "https://analytics.example.com")!)
        #expect(data.umamiID == "project-123")
        #expect(data.umamiAnalytics?.url == URL(string: "https://analytics.example.com")!)
        #expect(data.umamiAnalytics?.id == "project-123")
    }

    @Test func `decodeAddRegion degrades invalid optional fields gracefully`() {
        // Malformed region-id, missing optional URLs
        let urlString = "onebusaway://add-region?name=Minimal%20Region&oba-url=https%3A%2F%2Fapi.example.com&region-id=invalid_number"
        let url = URL(string: urlString)!
        let decoded = router.decodeURLType(from: url)

        guard case let .addRegion(dataOpt) = decoded, let data = dataOpt else {
            Issue.record("Expected non-nil addRegion data")
            return
        }

        #expect(data.name == "Minimal Region")
        #expect(data.regionID == nil) // Degrades to nil rather than failing
        #expect(data.obaURL == URL(string: "https://api.example.com")!)
        #expect(data.otpURL == nil)
        #expect(data.otpGraphQLURL == nil)
        #expect(data.supportsOTPGraphQLBikeshare == false)
        #expect(data.sidecarURL == nil)
        #expect(data.umamiAnalytics == nil)
    }

    @Test func `decodeAddRegion returns addRegion with nil data when required oba-url is missing or invalid`() {
        let missingOba = URL(string: "onebusaway://add-region?name=NoOBA")!
        let invalidOba = URL(string: "onebusaway://add-region?name=BadOBA&oba-url=")!

        guard case let .addRegion(data1) = router.decodeURLType(from: missingOba) else {
            Issue.record("Expected .addRegion enum")
            return
        }
        #expect(data1 == nil)

        guard case let .addRegion(data2) = router.decodeURLType(from: invalidOba) else {
            Issue.record("Expected .addRegion enum")
            return
        }
        #expect(data2 == nil)
    }

    // MARK: - Unknown Scheme and Host Fallbacks

    @Test func `decodeURLType returns nil for unrecognized host names`() {
        let unknownHost = URL(string: "onebusaway://unknown-action?param=value")!
        #expect(router.decodeURLType(from: unknownHost) == nil)
    }

    @Test func `decodeURLType returns nil for blank URL or missing host`() {
        let noHost = URL(string: "onebusaway://")!
        #expect(router.decodeURLType(from: noHost) == nil)
    }
}
