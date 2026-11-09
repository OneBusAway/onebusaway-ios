//
//  AppInteropTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class AppInteropTests {

    let seattleCoordinate = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)

    @Test func `Google Maps walking directions URL generation`() throws {
        let url = try #require(AppInterop.googleMapsWalkingDirectionsURL(coordinate: seattleCoordinate))

        #expect(url.scheme == "comgooglemaps")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        let daddr = components.queryItems?.first { $0.name == "daddr" }?.value
        let directionsMode = components.queryItems?.first { $0.name == "directionsmode" }?.value

        #expect(daddr == "47.6062,-122.3321")
        #expect(directionsMode == "walking")
    }

    @Test func `Apple Maps walking directions URL generation`() throws {
        let url = try #require(AppInterop.appleMapsWalkingDirectionsURL(coordinate: seattleCoordinate))

        #expect(url.scheme == "http")
        #expect(url.host == "maps.apple.com")

        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        let daddr = components.queryItems?.first { $0.name == "daddr" }?.value
        let dirflg = components.queryItems?.first { $0.name == "dirflg" }?.value

        #expect(daddr == "47.6062,-122.3321")
        #expect(dirflg == "w")
    }

    @Test func `Coordinates with negative and decimal boundaries`() throws {
        let southernHemisphere = CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093)

        let gUrl = try #require(AppInterop.googleMapsWalkingDirectionsURL(coordinate: southernHemisphere))
        let aUrl = try #require(AppInterop.appleMapsWalkingDirectionsURL(coordinate: southernHemisphere))

        let gComponents = try #require(URLComponents(url: gUrl, resolvingAgainstBaseURL: false))
        let aComponents = try #require(URLComponents(url: aUrl, resolvingAgainstBaseURL: false))

        #expect(gComponents.queryItems?.first { $0.name == "daddr" }?.value == "-33.8688,151.2093")
        #expect(aComponents.queryItems?.first { $0.name == "daddr" }?.value == "-33.8688,151.2093")
    }
}
