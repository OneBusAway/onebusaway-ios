//
//  RESTAPIServiceExtendedOperationsTests.swift
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
@testable import OBAKit
@testable import OBAKitCore

/// Extended test coverage for `RESTAPIService` service queries:
/// circular region stop discovery, bounding coordinate queries, route queries,
/// stop schedules, and error status handling.
@Suite(.serialized)
final class RESTAPIServiceExtendedOperationsTests: OBATestCase {

    private var dataLoader: MockDataLoader!

    override init() async throws {
        try await super.init()
        dataLoader = try #require(restService.dataLoader as? MockDataLoader)
    }

    // MARK: - getStops with Circular Region and Query

    @Test func `getStops with circularRegion and query crafts correct URL and decodes stops`() async throws {
        let center = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
        let circularRegion = CLCircularRegion(center: center, radius: 500, identifier: "test_circle")
        let query = "Downtown"

        let fixtureData = Fixtures.loadData(file: "stops_for_location_seattle.json")

        dataLoader.mock(data: fixtureData) { request in
            guard let url = request.url else { return false }
            return url.path.contains("/api/where/stops-for-location.json") &&
                url.containsQueryParams([
                    "lat": "47.6062",
                    "lon": "-122.3321",
                    "radius": "500",
                    "query": "Downtown"
                ])
        }

        let response = try await restService.getStops(circularRegion: circularRegion, query: query)
        #expect(!response.list.isEmpty)
        #expect(response.list.first?.name != nil)
    }

    // MARK: - getStops with Coordinate

    @Test func `getStops with single coordinate crafts correct location URL`() async throws {
        let coordinate = CLLocationCoordinate2D(latitude: 47.6097, longitude: -122.3331)
        let fixtureData = Fixtures.loadData(file: "stops_for_location_seattle.json")

        dataLoader.mock(data: fixtureData) { request in
            guard let url = request.url else { return false }
            return url.path.contains("/api/where/stops-for-location.json") &&
                url.containsQueryParams([
                    "lat": "47.6097",
                    "lon": "-122.3331"
                ])
        }

        let response = try await restService.getStops(coordinate: coordinate)
        #expect(!response.list.isEmpty)
    }

    // MARK: - getRoute with Circular Region

    @Test func `getRoute with query and circular region crafts routes-for-location request`() async throws {
        let center = CLLocationCoordinate2D(latitude: 47.6097, longitude: -122.3331)
        let circularRegion = CLCircularRegion(center: center, radius: 1000, identifier: "routes_circle")
        let query = "Downtown"

        let fixtureData = Fixtures.loadData(file: "routes_for_location_downtown_seattle1.json")

        dataLoader.mock(data: fixtureData) { request in
            guard let url = request.url else { return false }
            return url.path.contains("/api/where/routes-for-location.json") &&
                url.containsQueryParams([
                    "lat": "47.6097",
                    "lon": "-122.3331",
                    "radius": "40000.0",
                    "query": "Downtown"
                ])
        }

        let response = try await restService.getRoute(query: query, region: circularRegion)
        #expect(!response.list.isEmpty)
    }

    // MARK: - getScheduleForStop with Date

    @Test func `getScheduleForStop includes formatted date in request query`() async throws {
        let stopID = "1_75403"
        let date = Date(timeIntervalSince1970: 1_600_000_000)
        let fixtureData = Fixtures.loadData(file: "schedule-for-stop_1_75403.json")

        dataLoader.mock(data: fixtureData) { request in
            guard let url = request.url else { return false }
            return url.path.contains("/api/where/schedule-for-stop/\(stopID).json") &&
                url.containsQueryParams(["date": "2020-09-13"])
        }

        let response = try await restService.getScheduleForStop(stopID: stopID, date: date)
        #expect(response.entry.stopID == stopID)
    }

    // MARK: - getScheduleForRoute with Date

    @Test func `getScheduleForRoute includes formatted date in request query`() async throws {
        let routeID = "1_100223"
        let date = Date(timeIntervalSince1970: 1_600_000_000)
        let fixtureData = Fixtures.loadData(file: "schedule-for-route_1_100223.json")

        dataLoader.mock(data: fixtureData) { request in
            guard let url = request.url else { return false }
            return url.path.contains("/api/where/schedule-for-route/\(routeID).json") &&
                url.containsQueryParams(["date": "2020-09-13"])
        }

        let response = try await restService.getScheduleForRoute(routeID: routeID, date: date)
        #expect(response.entry.routeID == routeID)
    }

    // MARK: - HTTP Error Handling

    @Test func `RESTAPIService throws APIError on HTTP 404 response`() async throws {
        let nonExistentStopID = "999_nonexistent"
        let notFoundURL = restService.urlBuilder.getStop(stopID: nonExistentStopID)

        dataLoader.mock(
            data: Data("{\"code\": 404, \"text\": \"Not Found\"}".utf8),
            statusCode: 404
        ) { request in
            request.url?.path == notFoundURL.path
        }

        do {
            _ = try await restService.getStop(id: nonExistentStopID)
            Issue.record("Expected APIError.requestNotFound")
        } catch APIError.requestNotFound(let response) {
            #expect(response.statusCode == 404)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func `RESTAPIService throws APIError on HTTP 500 server error response`() async throws {
        let stopID = "1_10020"
        let serverErrorURL = restService.urlBuilder.getArrivalsAndDeparturesForStop(id: stopID, minutesBefore: 5, minutesAfter: 35)

        dataLoader.mock(
            data: Data("{\"code\": 500, \"text\": \"Internal Server Error\"}".utf8),
            statusCode: 500
        ) { request in
            request.url?.path == serverErrorURL.path
        }

        do {
            _ = try await restService.getArrivalsAndDeparturesForStop(id: stopID, minutesBefore: 5, minutesAfter: 35)
            Issue.record("Expected APIError.requestFailure")
        } catch APIError.requestFailure(let response) {
            #expect(response.statusCode == 500)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
