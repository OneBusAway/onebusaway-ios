//
//  RegionTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import MapKit
import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class RegionTests: OBATestCase {

    private func createTestRegion(
        bounds: [[String: Double]] = [
            ["lat": 47.6097, "lon": -122.3331, "latSpan": 0.5, "lonSpan": 0.5]
        ],
        paymentScheme: String? = nil,
        paymentWarningTitle: String? = nil,
        paymentWarningBody: String? = nil,
        openTripPlannerURL: String? = nil,
        openTripPlannerGraphQLURL: String? = nil,
        supportsOTPGraphQLBikeshare: Bool = false
    ) throws -> Region {
        var dict: [String: Any] = [
            "regionName": "Test Region",
            "id": 999,
            "obaBaseUrl": "https://example.com/api/",
            "siriBaseUrl": "",
            "bounds": bounds,
            "language": "en_US",
            "contactEmail": "test@example.com",
            "supportsObaDiscoveryApis": true,
            "supportsObaRealtimeApis": true,
            "supportsSiriRealtimeApis": false,
            "supportsEmbeddedSocial": false,
            "supportsOtpBikeshare": false,
            "supportsOtpGraphqlBikeshare": supportsOTPGraphQLBikeshare,
            "active": true,
            "experimental": false,
            "obaVersionInfo": "2.4.0|2|4|0"
        ]

        if let paymentScheme {
            dict["paymentiOSAppUrlScheme"] = paymentScheme
        }
        if let paymentWarningTitle {
            dict["paymentWarningTitle"] = paymentWarningTitle
        }
        if let paymentWarningBody {
            dict["paymentWarningBody"] = paymentWarningBody
        }
        if let openTripPlannerURL {
            dict["otpBaseUrl"] = openTripPlannerURL
        }
        if let openTripPlannerGraphQLURL {
            dict["otpBaseGraphqlUrl"] = openTripPlannerGraphQLURL
        }

        return try Fixtures.dictionaryToModel(type: Region.self, dictionary: dict)
    }

    // MARK: - OpenTripPlanner Capabilities

    @Test func `supportsOTP returns true when either GraphQL or REST URL is present`() throws {
        let restOnly = try createTestRegion(openTripPlannerURL: "https://otp.example.com/rest")
        #expect(restOnly.supportsOTP)

        let graphQLOnly = try createTestRegion(openTripPlannerGraphQLURL: "https://otp.example.com/graphql")
        #expect(graphQLOnly.supportsOTP)

        let neither = try createTestRegion()
        #expect(!neither.supportsOTP)
    }

    @Test func `isBikeshareEnabled requires both opt-in flag and GraphQL endpoint`() throws {
        let fullyConfigured = try createTestRegion(
            openTripPlannerGraphQLURL: "https://otp.example.com/graphql",
            supportsOTPGraphQLBikeshare: true
        )
        #expect(fullyConfigured.isBikeshareEnabled)

        let missingURL = try createTestRegion(
            openTripPlannerGraphQLURL: nil,
            supportsOTPGraphQLBikeshare: true
        )
        #expect(!missingURL.isBikeshareEnabled)

        let flagDisabled = try createTestRegion(
            openTripPlannerGraphQLURL: "https://otp.example.com/graphql",
            supportsOTPGraphQLBikeshare: false
        )
        #expect(!flagDisabled.isBikeshareEnabled)
    }

    // MARK: - Fare Payment

    @Test func `supportsMobileFarePayment reflects presence of iOS app URL scheme`() throws {
        let withScheme = try createTestRegion(paymentScheme: "orca-card")
        #expect(withScheme.supportsMobileFarePayment)
        #expect(withScheme.paymentAppDeepLinkURL?.absoluteString == "orca-card://onebusaway")

        let withoutScheme = try createTestRegion(paymentScheme: nil)
        #expect(!withoutScheme.supportsMobileFarePayment)
        #expect(withoutScheme.paymentAppDeepLinkURL == nil)
    }

    @Test func `paymentAppDoesNotCoverFullRegion requires both title and body`() throws {
        let partialCoverage = try createTestRegion(
            paymentScheme: "app",
            paymentWarningTitle: "Notice",
            paymentWarningBody: "Fares not supported on ferries"
        )
        #expect(partialCoverage.paymentAppDoesNotCoverFullRegion)

        let titleOnly = try createTestRegion(
            paymentScheme: "app",
            paymentWarningTitle: "Notice",
            paymentWarningBody: nil
        )
        #expect(!titleOnly.paymentAppDoesNotCoverFullRegion)

        let bodyOnly = try createTestRegion(
            paymentScheme: "app",
            paymentWarningTitle: nil,
            paymentWarningBody: "Body text"
        )
        #expect(!bodyOnly.paymentAppDoesNotCoverFullRegion)

        let neither = try createTestRegion(paymentScheme: "app")
        #expect(!neither.paymentAppDoesNotCoverFullRegion)
    }

    // MARK: - Location Helpers

    @Test func `contains returns true for coordinates inside bounds and false outside`() throws {
        // Center: (47.6097, -122.3331) with span: 0.5 lat and 0.5 lon
        let region = try createTestRegion(bounds: [
            ["lat": 47.6097, "lon": -122.3331, "latSpan": 0.5, "lonSpan": 0.5]
        ])

        let insideLoc = CLLocation(latitude: 47.6097, longitude: -122.3331)
        #expect(region.contains(location: insideLoc))

        let nearEdgeInside = CLLocation(latitude: 47.7, longitude: -122.3)
        #expect(region.contains(location: nearEdgeInside))

        let farOutside = CLLocation(latitude: 28.0587, longitude: -82.4139) // Tampa
        #expect(!region.contains(location: farOutside))

        #expect(!region.contains(location: nil))
    }

    @Test func `contains supports multi-bound region unions`() throws {
        let multiBoundRegion = try createTestRegion(bounds: [
            ["lat": 47.0, "lon": -122.0, "latSpan": 0.2, "lonSpan": 0.2],
            ["lat": 48.0, "lon": -122.0, "latSpan": 0.2, "lonSpan": 0.2]
        ])

        let loc1 = CLLocation(latitude: 47.05, longitude: -122.0)
        let loc2 = CLLocation(latitude: 47.95, longitude: -122.0)
        let locBetween = CLLocation(latitude: 47.5, longitude: -122.0) // Inside bounding serviceRect

        #expect(multiBoundRegion.contains(location: loc1))
        #expect(multiBoundRegion.contains(location: loc2))
        #expect(multiBoundRegion.contains(location: locBetween))
    }

    @Test func `distanceFrom calculates distance from region center`() throws {
        let centerLat = 47.6097
        let centerLon = -122.3331
        let region = try createTestRegion(bounds: [
            ["lat": centerLat, "lon": centerLon, "latSpan": 0.5, "lonSpan": 0.5]
        ])

        let centerLoc = CLLocation(latitude: centerLat, longitude: centerLon)
        let distanceAtCenter = region.distanceFrom(location: centerLoc)
        #expect(distanceAtCenter < 50.0) // Within 50 meters of calculated center

        let offsetLoc = CLLocation(latitude: 47.7, longitude: -122.3331)
        let distanceOffset = region.distanceFrom(location: offsetLoc)
        #expect(distanceOffset > 5000.0) // ~10 km away
    }

    // MARK: - Open311Server

    @Test func `Open311Server decodes, round-trips, and participates in equality`() throws {
        let json = """
        {
            "jurisdictionId": "city-seattle",
            "apiKey": "key_open311_123",
            "baseUrl": "https://seeclickfix.com/open311/v2"
        }
        """
        let server = try JSONDecoder().decode(Open311Server.self, from: Data(json.utf8))
        #expect(server.jurisdictionID == "city-seattle")
        #expect(server.apiKey == "key_open311_123")
        #expect(server.baseURL.absoluteString == "https://seeclickfix.com/open311/v2")

        let encoded = try JSONEncoder().encode(server)
        let roundTripped = try JSONDecoder().decode(Open311Server.self, from: encoded)
        #expect(server == roundTripped)

        let diffServer = try JSONDecoder().decode(Open311Server.self, from: Data("""
        {
            "jurisdictionId": "city-bellevue",
            "apiKey": "key_open311_123",
            "baseUrl": "https://seeclickfix.com/open311/v2"
        }
        """.utf8))
        #expect(server != diffServer)
    }

    @Test func `Open311Server decodes with nil optional jurisdictionId`() throws {
        let json = """
        {
            "apiKey": "key_simple",
            "baseUrl": "https://open311.example.com"
        }
        """
        let server = try JSONDecoder().decode(Open311Server.self, from: Data(json.utf8))
        #expect(server.jurisdictionID == nil)
        #expect(server.apiKey == "key_simple")
        #expect(server.baseURL.absoluteString == "https://open311.example.com")
    }
}
