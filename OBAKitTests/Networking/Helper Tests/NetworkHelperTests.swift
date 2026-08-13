//
//  NetworkHelperTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import CoreLocation
import MapKit

@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class NetworkHelperTests: OBATestCase {
    @Test func `Dictionary to query items success`() {
        let dict: [String: Any] = ["one": 2, "three": "four"]
        let queryItems = NetworkHelpers.dictionary(toQueryItems: dict).sorted(by: { $0.name < $1.name })

        let qi1 = queryItems.first!
        let qi2 = queryItems.last!

        #expect(qi1.name == "one")
        #expect(qi1.value == "2")

        #expect(qi2.name == "three")
        #expect(qi2.value == "four")
    }

    /// Tests that Double values use period (.) as decimal separator regardless of locale.
    /// This is critical for API compatibility - servers expect US-style decimal formatting.
    /// Bug: https://github.com/OneBusAway/onebusaway-iphone/issues/1024
    @Test func `Dictionary to query items double values use locale independent formatting`() {
        // Simulate a German locale where decimal separator is comma
        let germanLocale = Locale(identifier: "de_DE")

        // Verify the locale would format with comma (proving our test premise)
        let commaFormattedNumber = String(format: "%g", locale: germanLocale, 47.61098)
        #expect(commaFormattedNumber.contains(","), "German locale should use comma as decimal separator")

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
            #expect(item.value?.contains(",") == false, "Query param '\(item.name)' should not contain comma")

            // Verify the actual expected values
            switch item.name {
            case "lat":
                #expect(item.value == "47.61098")
            case "lon":
                #expect(item.value == "-122.33845")
            case "latSpan":
                #expect(item.value == "0.005")
            case "lonSpan":
                #expect(item.value == "0.008")
            default:
                Issue.record("Unexpected query item: \(item.name)")
            }
        }
    }

    /// Tests that Float values also use locale-independent formatting
    @Test func `Dictionary to query items float values use locale independent formatting`() {
        let dict: [String: Any] = [
            "value": Float(3.14159)
        ]

        let queryItems = NetworkHelpers.dictionary(toQueryItems: dict)
        let item = queryItems.first!

        #expect(item.value?.contains(",") == false)
        #expect(item.value == "3.14159")
    }

    /// Tests the actual URL building for stops-for-location endpoint
    @Test func `RESTAPIURL builder stops for location uses correct decimal format`() {
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
        #expect(!urlString.contains("47,"))
        #expect(!urlString.contains("-122,"))
        #expect(!urlString.contains("0,005"))
        #expect(!urlString.contains("0,008"))

        // Verify correct format
        #expect(urlString.contains("lat=47.61098"))
        #expect(urlString.contains("lon=-122.33845"))
        #expect(urlString.contains("latSpan=0.005"))
        #expect(urlString.contains("lonSpan=0.008"))
    }

    @Test func `Dictionary to HTTP body data`() {
        let dict: [String: Any] = ["one": 2, "three": "four"]
        let data = NetworkHelpers.dictionary(toHTTPBodyData: dict)

        let expectedData1 = "one=2&three=four".data(using: .utf8)
        let match1 = (expectedData1 == data)

        let expectedData2 = "three=four&one=2".data(using: .utf8)
        let match2 = (expectedData2 == data)

        #expect((match1 || match2))
    }

    /// Tests that Double values in HTTP body use period as decimal separator regardless of locale
    @Test func `Dictionary to HTTP body data double values use locale independent formatting`() {
        let dict: [String: Any] = [
            "lat": 47.61098,
            "lon": -122.33845
        ]

        let data = NetworkHelpers.dictionary(toHTTPBodyData: dict)
        let bodyString = String(data: data, encoding: .utf8)!

        // Should not contain comma as decimal separator
        // The string should be like "lat=47.61098&lon=-122.33845" (order may vary)
        #expect(!bodyString.contains("47,"))
        #expect(!bodyString.contains("-122,"))
        #expect(bodyString.contains("47.61098"))
        #expect(bodyString.contains("-122.33845"))
    }

    /// Tests that REST API requests include Accept-Language header set to en-US
    /// to prevent server-side locale-dependent number parsing issues.
    /// Bug: Server returns 400 when Accept-Language is non-English because it
    /// parses lat/lon with locale-aware number parsing.
    @Test func `RESTAPI service sets accept language header`() async throws {
        // Boxed: the matcher is @Sendable and cannot write to a main-actor local.
        let capturedRequest = SendableBox<URLRequest?>(nil)

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
            capturedRequest.value = request
            return request.url?.path.contains("stops-for-location") == true
        }
        mockDataLoader.mock(response: mockResponse)

        let restService = buildRESTService(dataLoader: mockDataLoader)
        let coordinate = CLLocationCoordinate2D(latitude: 47.61098, longitude: -122.33845)

        _ = try? await restService.getStops(coordinate: coordinate)

        // Verify Accept-Language header is set to en-US
        #expect(capturedRequest.value != nil)
        let acceptLanguage = capturedRequest.value?.value(forHTTPHeaderField: "Accept-Language")
        #expect(acceptLanguage == "en-US")
    }
}
