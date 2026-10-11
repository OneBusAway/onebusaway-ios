//
//  SearchModelTests.swift
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

@Suite(.serialized)
@MainActor
struct SearchModelTests {

    private func englishBundle() -> Bundle? {
        guard let path = Bundle(for: DonationCell.self).path(forResource: "en", ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    // MARK: - SearchRequest

    @Test func `SearchRequest retains query and search type`() {
        let req1 = SearchRequest(query: "Broadway & Pike", type: .address)
        #expect(req1.query == "Broadway & Pike")
        #expect(req1.searchType == .address)

        let req2 = SearchRequest(query: "49", type: .route)
        #expect(req2.query == "49")
        #expect(req2.searchType == .route)

        let req3 = SearchRequest(query: "1_75403", type: .stopNumber)
        #expect(req3.query == "1_75403")
        #expect(req3.searchType == .stopNumber)

        let req4 = SearchRequest(query: "4321", type: .vehicleID)
        #expect(req4.query == "4321")
        #expect(req4.searchType == .vehicleID)
    }

    // MARK: - SearchResponse

    @Test func `SearchResponse initialization stores all properties`() {
        let request = SearchRequest(query: "10", type: .route)
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
        let results: [Any] = ["Route 10", "Route 10 Express"]

        let response = SearchResponse(
            request: request,
            results: results,
            boundingRegion: region,
            error: nil
        )

        #expect(response.request === request)
        #expect(response.results.count == 2)
        #expect(response.boundingRegion?.center.latitude == region.center.latitude)
        #expect(response.boundingRegion?.center.longitude == region.center.longitude)
        #expect(response.error == nil)
    }

    @Test func `SearchResponse needsDisambiguation behaves correctly based on result count`() {
        let request = SearchRequest(query: "Downtown", type: .address)

        // 0 results: needs disambiguation / direct display is not possible
        let emptyResponse = SearchResponse(request: request, results: [], boundingRegion: nil, error: nil)
        #expect(emptyResponse.needsDisambiguation)

        // Exactly 1 result: does NOT need disambiguation (can show directly)
        let singleResponse = SearchResponse(request: request, results: ["Pike Place"], boundingRegion: nil, error: nil)
        #expect(!singleResponse.needsDisambiguation)

        // Multiple results: needs disambiguation
        let multiResponse = SearchResponse(request: request, results: ["Pike Place", "Westlake"], boundingRegion: nil, error: nil)
        #expect(multiResponse.needsDisambiguation)
    }

    @Test func `SearchResponse substituteResult initializer creates single result response while preserving metadata`() {
        let request = SearchRequest(query: "Route 8", type: .route)
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        let original = SearchResponse(
            request: request,
            results: ["Candidate 1", "Candidate 2"],
            boundingRegion: region,
            error: SearchError.noTripsAvailable
        )

        let substituted = SearchResponse(response: original, substituteResult: "Selected Route")

        #expect(substituted.request === original.request)
        #expect(substituted.results.count == 1)
        #expect(substituted.results.first as? String == "Selected Route")
        #expect(!substituted.needsDisambiguation)
        #expect(substituted.boundingRegion?.center.latitude == region.center.latitude)
        #expect((substituted.error as? SearchError) == .noTripsAvailable)
    }

    // MARK: - SearchError

    @Test func `SearchError noTripsAvailable localized description and key resolution`() throws {
        let bundle = try #require(englishBundle())
        let key = "search_results_controller.no_trips_available"

        let localized = bundle.localizedString(forKey: key, value: "MISSING", table: nil)
        #expect(localized != "MISSING", "\(key) is missing from the English catalog")
        #expect(localized == "This vehicle is not currently on any trips.")

        let error = SearchError.noTripsAvailable
        #expect(error.errorDescription == "This vehicle is not currently on any trips.")
        #expect(error.localizedDescription == "This vehicle is not currently on any trips.")
    }
}
