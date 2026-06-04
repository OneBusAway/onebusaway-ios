//
//  AppLinksRouterDeepLinkFormatTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import XCTest
import Nimble
@testable import OBAKitCore

/// Tests the deep link URL format for trip sharing, specifically the `destination_stop_id` parameter.
/// These tests verify URL construction and parsing without requiring a full `Application` object.
/// See: https://github.com/OneBusAway/onebusaway-ios/issues/449
class AppLinksRouterDeepLinkFormatTests: XCTestCase {

    // MARK: - URL Construction with destination_stop_id

    func test_urlWithDestinationStopID_containsQueryParam() {
        var components = URLComponents(string: "https://onebusaway.co")!
        components.path = "/regions/1/stops/1_75403/trips"

        var queryItems = [
            URLQueryItem(name: "trip_id", value: "1_550_trip"),
            URLQueryItem(name: "service_date", value: "1710273600.0"),
            URLQueryItem(name: "stop_sequence", value: "12")
        ]
        queryItems.append(URLQueryItem(name: "destination_stop_id", value: "1_431"))
        components.queryItems = queryItems

        let url = components.url!
        let parsed = URLComponents(url: url, resolvingAgainstBaseURL: false)!

        expect(parsed.queryItem(named: "destination_stop_id")?.value) == "1_431"
        expect(parsed.queryItem(named: "trip_id")?.value) == "1_550_trip"
        expect(parsed.queryItem(named: "service_date")?.value) == "1710273600.0"
        expect(parsed.queryItem(named: "stop_sequence")?.value) == "12"
    }

    func test_urlWithoutDestinationStopID_doesNotContainQueryParam() {
        var components = URLComponents(string: "https://onebusaway.co")!
        components.path = "/regions/1/stops/1_75403/trips"
        components.queryItems = [
            URLQueryItem(name: "trip_id", value: "1_550_trip"),
            URLQueryItem(name: "service_date", value: "1710273600.0"),
            URLQueryItem(name: "stop_sequence", value: "12")
        ]

        let url = components.url!
        let parsed = URLComponents(url: url, resolvingAgainstBaseURL: false)!

        expect(parsed.queryItem(named: "destination_stop_id")).to(beNil())
        expect(parsed.queryItems?.count) == 3
    }

    func test_destinationStopIDWithSpecialCharacters_encodedCorrectly() {
        var components = URLComponents(string: "https://onebusaway.co")!
        components.path = "/regions/1/stops/1_75403/trips"
        components.queryItems = [
            URLQueryItem(name: "trip_id", value: "1_trip"),
            URLQueryItem(name: "service_date", value: "1710273600.0"),
            URLQueryItem(name: "stop_sequence", value: "5"),
            URLQueryItem(name: "destination_stop_id", value: "Hillsborough Area Regional Transit_4712")
        ]

        let url = components.url!
        let parsed = URLComponents(url: url, resolvingAgainstBaseURL: false)!

        expect(parsed.queryItem(named: "destination_stop_id")?.value) == "Hillsborough Area Regional Transit_4712"
    }

    // MARK: - Deep Link Model from URL with destination_stop_id

    func test_deepLinkInit_withDestinationStopID_setsProperty() {
        let link = ArrivalDepartureDeepLink(
            title: "545 - Seattle",
            regionID: 1,
            stopID: "1_75403",
            tripID: "1_545_trip",
            serviceDate: Date(timeIntervalSince1970: 1_710_273_600),
            stopSequence: 12,
            vehicleID: "1_v100",
            destinationStopID: "1_431"
        )

        expect(link.destinationStopID) == "1_431"
        expect(link.stopID) == "1_75403"
        expect(link.regionID) == 1
    }

    func test_deepLinkInit_withoutDestinationStopID_isNil() {
        let link = ArrivalDepartureDeepLink(
            title: "545 - Seattle",
            regionID: 1,
            stopID: "1_75403",
            tripID: "1_545_trip",
            serviceDate: Date(timeIntervalSince1970: 1_710_273_600),
            stopSequence: 12,
            vehicleID: nil
        )

        expect(link.destinationStopID).to(beNil())
    }

    // MARK: - Backward Compatibility

    func test_backwardCompatibility_existingURLFormat_parsesWithoutDestination() {
        // Simulates a URL from an older client that doesn't include destination_stop_id
        let urlString = "https://onebusaway.co/regions/1/stops/1_75403/trips?trip_id=1_545_trip&service_date=1710273600.0&stop_sequence=12"
        let url = URL(string: urlString)!
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!

        expect(components.queryItem(named: "destination_stop_id")).to(beNil())
        expect(components.queryItem(named: "trip_id")?.value) == "1_545_trip"
        expect(components.queryItem(named: "stop_sequence")?.value) == "12"
    }

    func test_backwardCompatibility_newURLFormat_parsesWithDestination() {
        // Simulates a URL from a new client that includes destination_stop_id
        let urlString = "https://onebusaway.co/regions/1/stops/1_75403/trips?trip_id=1_545_trip&service_date=1710273600.0&stop_sequence=12&destination_stop_id=1_431"
        let url = URL(string: urlString)!
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!

        expect(components.queryItem(named: "destination_stop_id")?.value) == "1_431"
        expect(components.queryItem(named: "trip_id")?.value) == "1_545_trip"
    }
}

private extension URLComponents {
    func queryItem(named name: String) -> URLQueryItem? {
        return queryItems?.first { $0.name == name }
    }
}
