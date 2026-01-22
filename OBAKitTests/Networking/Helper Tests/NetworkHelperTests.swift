//
//  NetworkHelperTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import XCTest
import Nimble
import CoreLocation
import MapKit

@testable import OBAKit
@testable import OBAKitCore

class NetworkHelperTests: OBATestCase {
    func testDictionaryToQueryItems_success() {
        let dict: [String: Any] = ["one": 2, "three": "four"]
        let queryItems = NetworkHelpers.dictionary(toQueryItems: dict).sorted(by: { $0.name < $1.name })

        let qi1 = queryItems.first!
        let qi2 = queryItems.last!

        expect(qi1.name) == "one"
        expect(qi1.value) == "2"

        expect(qi2.name) == "three"
        expect(qi2.value) == "four"
    }

    /// Tests that Double values use period (.) as decimal separator regardless of locale.
    /// This is critical for API compatibility - servers expect US-style decimal formatting.
    /// Bug: https://github.com/OneBusAway/onebusaway-iphone/issues/1024
    func testDictionaryToQueryItems_doubleValuesUseLocaleIndependentFormatting() {
        // Simulate a German locale where decimal separator is comma
        let germanLocale = Locale(identifier: "de_DE")

        // Verify the locale would format with comma (proving our test premise)
        let commaFormattedNumber = String(format: "%g", locale: germanLocale, 47.61098)
        expect(commaFormattedNumber).to(contain(","), description: "German locale should use comma as decimal separator")

        // The actual values that would be sent for stops-for-location API
        let dict: [String: Any] = [
            "lat": 47.61098,
            "lon": -122.33845,
            "latSpan": 0.005,
            "lonSpan": 0.008
        ]

        let queryItems = NetworkHelpers.dictionary(toQueryItems: dict)

        // All values must use period as decimal separator for API compatibility
        for item in queryItems {
            expect(item.value).notTo(contain(","), description: "Query param '\(item.name)' should not contain comma")

            // Verify the actual expected values
            switch item.name {
            case "lat":
                expect(item.value) == "47.61098"
            case "lon":
                expect(item.value) == "-122.33845"
            case "latSpan":
                expect(item.value) == "0.005"
            case "lonSpan":
                expect(item.value) == "0.008"
            default:
                fail("Unexpected query item: \(item.name)")
            }
        }
    }

    /// Tests that Float values also use locale-independent formatting
    func testDictionaryToQueryItems_floatValuesUseLocaleIndependentFormatting() {
        let dict: [String: Any] = [
            "value": Float(3.14159)
        ]

        let queryItems = NetworkHelpers.dictionary(toQueryItems: dict)
        let item = queryItems.first!

        expect(item.value).notTo(contain(","))
        expect(item.value) == "3.14159"
    }

    /// Tests the actual URL building for stops-for-location endpoint
    func testRESTAPIURLBuilder_stopsForLocation_usesCorrectDecimalFormat() {
        let baseURL = URL(string: "https://api.example.com")!
        let queryItems = [URLQueryItem(name: "key", value: "test")]
        let urlBuilder = RESTAPIURLBuilder(baseURL: baseURL, defaultQueryItems: queryItems)

        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 47.61098, longitude: -122.33845),
            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.008)
        )

        let url = urlBuilder.getStops(region: region)
        let urlString = url.absoluteString

        // URL must use period as decimal separator, never comma
        expect(urlString).notTo(contain("47,"))
        expect(urlString).notTo(contain("-122,"))
        expect(urlString).notTo(contain("0,005"))
        expect(urlString).notTo(contain("0,008"))

        // Verify correct format
        expect(urlString).to(contain("lat=47.61098"))
        expect(urlString).to(contain("lon=-122.33845"))
        expect(urlString).to(contain("latSpan=0.005"))
        expect(urlString).to(contain("lonSpan=0.008"))
    }

    func testDictionaryToHTTPBodyData() {
        let dict: [String: Any] = ["one": 2, "three": "four"]
        let data = NetworkHelpers.dictionary(toHTTPBodyData: dict)

        let expectedData1 = "one=2&three=four".data(using: .utf8)
        let match1 = (expectedData1 == data)

        let expectedData2 = "three=four&one=2".data(using: .utf8)
        let match2 = (expectedData2 == data)

        expect(match1 || match2).to(beTrue())
    }

    /// Tests that Double values in HTTP body use period as decimal separator regardless of locale
    func testDictionaryToHTTPBodyData_doubleValuesUseLocaleIndependentFormatting() {
        let dict: [String: Any] = [
            "lat": 47.61098,
            "lon": -122.33845
        ]

        let data = NetworkHelpers.dictionary(toHTTPBodyData: dict)
        let bodyString = String(data: data, encoding: .utf8)!

        // Should not contain comma as decimal separator
        // The string should be like "lat=47.61098&lon=-122.33845" (order may vary)
        expect(bodyString).notTo(contain("47,"))
        expect(bodyString).notTo(contain("-122,"))
        expect(bodyString).to(contain("47.61098"))
        expect(bodyString).to(contain("-122.33845"))
    }

    /// Tests that REST API requests include Accept-Language header set to en-US
    /// to prevent server-side locale-dependent number parsing issues.
    /// Bug: Server returns 400 when Accept-Language is non-English because it
    /// parses lat/lon with locale-aware number parsing.
    func testRESTAPIService_setsAcceptLanguageHeader() async throws {
        var capturedRequest: URLRequest?

        let mockDataLoader = MockDataLoader(testName: name)
        // Set up a matcher that captures the request for inspection
        let mockResponse = MockDataResponse(
            data: Fixtures.loadData(file: "stops_for_location_downtown_seattle1.json"),
            urlResponse: HTTPURLResponse(
                url: URL(string: "https://www.example.com/api/where/stops-for-location.json")!,
                statusCode: 200,
                httpVersion: "2",
                headerFields: ["Content-Type": "application/json"]
            ),
            error: nil
        ) { request in
            capturedRequest = request
            return request.url?.path.contains("stops-for-location") == true
        }
        mockDataLoader.mock(response: mockResponse)

        let restService = buildRESTService(dataLoader: mockDataLoader)
        let coordinate = CLLocationCoordinate2D(latitude: 47.61098, longitude: -122.33845)

        _ = try? await restService.getStops(coordinate: coordinate)

        // Verify Accept-Language header is set to en-US
        expect(capturedRequest).notTo(beNil())
        let acceptLanguage = capturedRequest?.value(forHTTPHeaderField: "Accept-Language")
        expect(acceptLanguage) == "en-US"
    }
}
