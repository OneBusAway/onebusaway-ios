//
//  RouteSearchModelOperationTests.swift
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

// swiftlint:disable force_cast

@Suite(.serialized)
final class RouteSearchModelOperationTests: OBATestCase {
    let query = "Link"
    let center = CLLocationCoordinate2D(latitude: 47.0, longitude: -122)
    let radius = 5000.0
    lazy var region = CLCircularRegion(center: center, radius: radius, identifier: "identifier")

    @Test func `Loading success`() async throws {
        let dataLoader = (restService.dataLoader as! MockDataLoader)
        let data = Fixtures.loadData(file: "routes-for-location-10.json")
        dataLoader.mock(URLString: "https://www.example.com/api/where/routes-for-location.json", with: data)

        let response = try await restService.getRoute(query: query, region: region)
        let routes = response.list

        #expect(routes.count == 1)

        let route = try #require(routes.first)

        #expect(route.agency.id == "1")
        #expect(route.agency.name == "Metro Transit")
        #expect(route.color == nil)
        #expect(route.routeDescription == "Capitol Hill - Downtown Seattle")
        #expect(route.id == "1_100002")
        #expect(route.longName == nil)
        #expect(route.shortName == "10")
        #expect(route.textColor == nil)
        #expect(route.routeType == .bus)
        #expect(route.routeURL == URL(string: "http://metro.kingcounty.gov/schedules/010/n0.html")!)
    }
}
