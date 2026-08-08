//
//  SearchManagerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// `fetchResults` is the returning entry point the SwiftUI panel consumes. These
/// tests pin its output per search type; `search(request:)`'s publishing behavior for
/// the UIKit path is covered separately at the end.
@Suite(.serialized)
final class SearchManagerTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    // MARK: - Stubs

    private func stubStopsForLocation(dataLoader: MockDataLoader) {
        let data = Fixtures.loadData(file: "stops_for_location_seattle.json")
        dataLoader.mock(data: data) { request in
            request.url?.path.contains("/api/where/stops-for-location.json") ?? false
        }
    }

    private func stubRoutesForLocation(dataLoader: MockDataLoader) {
        let data = Fixtures.loadData(file: "routes_for_location_query.json")
        dataLoader.mock(data: data) { request in
            request.url?.path.contains("/api/where/routes-for-location.json") ?? false
        }
    }

    // MARK: - Stop number

    @Test @MainActor
    func `Fetch results for a stop number returns the matching stops`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        stubStopsForLocation(dataLoader: dataLoader)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let manager = SearchManager(application: application)

        let request = SearchRequest(query: "1_75403", type: .stopNumber)
        let response = try #require(await manager.fetchResults(for: request))

        #expect(response.request === request)
        #expect(response.results.isEmpty == false)
        #expect(response.results.allSatisfy { $0 is Stop })
    }

    // MARK: - Route

    @Test @MainActor
    func `Fetch results for a route returns the matching routes`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        stubRoutesForLocation(dataLoader: dataLoader)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let manager = SearchManager(application: application)

        let request = SearchRequest(query: "44", type: .route)
        let response = try #require(await manager.fetchResults(for: request))

        #expect(response.results.allSatisfy { $0 is Route })
    }

    // MARK: - Errors are thrown, not swallowed

    @Test @MainActor
    func `Fetch results throws when the route request fails`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: "not json".data(using: .utf8)!) { request in
            request.url?.path.contains("/api/where/routes-for-location.json") ?? false
        }
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let manager = SearchManager(application: application)

        await #expect(throws: (any Error).self) {
            _ = try await manager.fetchResults(for: SearchRequest(query: "44", type: .route))
        }
    }

    // MARK: - The search region comes from lastVisibleMapRect

    @Test @MainActor
    func `Route search queries the recorded viewport`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        stubRoutesForLocation(dataLoader: dataLoader)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        // A small rect near Seattle; the request's lat/lon must land inside it.
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3),
            latitudinalMeters: 2_000,
            longitudinalMeters: 2_000
        )
        application.mapRegionManager.lastVisibleMapRect = MKMapRect(region)

        let manager = SearchManager(application: application)
        _ = try await manager.fetchResults(for: SearchRequest(query: "44", type: .route))

        let sent = try #require(dataLoader.requests.first { $0.url?.path.contains("routes-for-location") ?? false })
        let url = try #require(sent.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let lat = try #require(components.queryItems?.first { $0.name == "lat" }?.value.flatMap(Double.init))
        let lon = try #require(components.queryItems?.first { $0.name == "lon" }?.value.flatMap(Double.init))

        #expect(abs(lat - 47.6) < 0.05)
        #expect(abs(lon - (-122.3)) < 0.05)
    }

    // MARK: - The UIKit path still publishes

    @Test @MainActor
    func `Search publishes the response to the region manager`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        stubStopsForLocation(dataLoader: dataLoader)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let manager = SearchManager(application: application)

        await manager.search(request: SearchRequest(query: "1_75403", type: .stopNumber))

        #expect(application.mapRegionManager.searchResponse != nil)
    }
}
