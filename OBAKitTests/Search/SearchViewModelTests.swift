//
//  SearchViewModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try

@Suite(.serialized)
final class SearchViewModelTests: OBATestCase {

    // MARK: - Helpers

    let vehicleID = "1_4351"
    lazy var vehicleURLString = "https://www.example.com/api/where/vehicle/\(vehicleID).json"

    func makeSearchResponse(
        searchType: SearchType,
        query: String = "test",
        results: [Any] = []
    ) -> SearchResponse {
        SearchResponse(request: SearchRequest(query: query, type: searchType), results: results, boundingRegion: nil, error: nil)
    }

    func makeSuccessLoader() -> MockDataLoader {
        let loader = MockDataLoader(testName: name)
        loader.mock(URLString: vehicleURLString, with: Fixtures.loadData(file: "api_where_vehicle_1_4351.json"))
        return loader
    }

    func makeNetworkErrorLoader() -> MockDataLoader {
        let loader = MockDataLoader(testName: name)
        let error = NSError(domain: "SearchViewModelTests", code: 500, userInfo: nil)
        loader.mock(response: MockDataResponse(data: nil, urlResponse: nil, error: error) { _ in true })
        return loader
    }

    func makeKeyNotFoundLoader() -> MockDataLoader {
        // Returns a valid VehicleStatus envelope but with `tripId` omitted from `entry`,
        // mirroring the real "vehicle isn't on any trip" payload — this is the specific
        // keyNotFound case SearchViewModel maps to `noTripsAvailable`. Other missing
        // keys (envelope, tripStatus, etc.) deliberately do *not* map to that error.
        let loader = MockDataLoader(testName: name)
        let json = #"""
        {"code":200,"currentTime":1588888802143,"data":{"entry":{"lastUpdateTime":1588888744000,"lastLocationUpdateTime":1588888744000,"phase":"in_progress","status":"SCHEDULED","tripStatus":{"activeTripId":"","blockTripSequence":0,"closestStop":"","closestStopTimeOffset":0,"distanceAlongTrip":0,"lastKnownDistanceAlongTrip":0,"lastLocationUpdateTime":0,"lastUpdateTime":0,"nextStop":"","nextStopTimeOffset":0,"orientation":0,"phase":"","position":{"lat":0,"lon":0},"predicted":false,"scheduleDeviation":0,"scheduledDistanceAlongTrip":0,"serviceDate":0,"situationIds":[],"status":"","totalDistanceAlongTrip":0,"vehicleId":""},"vehicleId":"1_4351"},"references":{"agencies":[],"routes":[],"situations":[],"stops":[],"trips":[]}},"text":"OK","version":2}
        """#
        loader.mock(URLString: vehicleURLString, with: Data(json.utf8))
        return loader
    }

    // MARK: - Subtitle

    @Test @MainActor
    func `Subtitle address is query verbatim`() {
        let vm = SearchViewModel(searchResponse: makeSearchResponse(searchType: .address, query: "Seattle, WA"), apiService: nil)
        #expect(vm.subtitle == "Seattle, WA")
    }

    @Test @MainActor
    func `Subtitle route prefixed with route`() {
        let vm = SearchViewModel(searchResponse: makeSearchResponse(searchType: .route, query: "44"), apiService: nil)
        #expect(vm.subtitle == "Route 44")
    }

    @Test @MainActor
    func `Subtitle stop number prefixed with stop number`() {
        let vm = SearchViewModel(searchResponse: makeSearchResponse(searchType: .stopNumber, query: "1234"), apiService: nil)
        #expect(vm.subtitle == "Stop number 1234")
    }

    @Test @MainActor
    func `Subtitle vehicle ID prefixed with vehicle ID`() {
        let vm = SearchViewModel(searchResponse: makeSearchResponse(searchType: .vehicleID, query: "XYZ"), apiService: nil)
        #expect(vm.subtitle == "Vehicle ID XYZ")
    }

    // MARK: - results

    @Test @MainActor
    func `Results matches search response results`() throws {
        let stop = try Fixtures.loadSomeStops().first!
        let vm = SearchViewModel(searchResponse: makeSearchResponse(searchType: .stopNumber, results: [stop]), apiService: nil)
        #expect(vm.results.count == 1)
        #expect((vm.results.first as? Stop) === stop)
    }

    // MARK: - response(substituting:)

    @Test @MainActor
    func `Response substituting single result is substitute`() throws {
        let stops = try Fixtures.loadSomeStops()
        let vm = SearchViewModel(searchResponse: makeSearchResponse(searchType: .stopNumber, results: [stops[0]]), apiService: nil)

        let substituted = vm.response(substituting: stops[1])

        #expect(substituted.results.count == 1)
        #expect((substituted.results.first as? Stop) === stops[1])
    }

    @Test @MainActor
    func `Response substituting preserves original request`() throws {
        let vm = SearchViewModel(searchResponse: makeSearchResponse(searchType: .route, query: "44"), apiService: nil)
        let substituted = vm.response(substituting: "anything")
        #expect(substituted.request.query == "44")
        #expect(substituted.request.searchType == .route)
    }

    @Test @MainActor
    func `Response substituting preserves bounding region`() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
        let searchResponse = SearchResponse(request: SearchRequest(query: "test", type: .address), results: [], boundingRegion: region, error: nil)
        let vm = SearchViewModel(searchResponse: searchResponse, apiService: nil)

        let substituted = vm.response(substituting: "anything")

        #expect(substituted.boundingRegion != nil)
        #expect(substituted.boundingRegion?.center.latitude == 47.6)
        #expect(substituted.boundingRegion?.center.longitude == -122.3)
    }

    @Test @MainActor
    func `Response substituting preserves error`() {
        let searchResponse = SearchResponse(request: SearchRequest(query: "test", type: .address), results: [], boundingRegion: nil, error: SearchError.noTripsAvailable)
        let vm = SearchViewModel(searchResponse: searchResponse, apiService: nil)

        let substituted = vm.response(substituting: "anything")

        #expect((substituted.error as? SearchError) == .noTripsAvailable)
    }

    // MARK: - Initial State

    @Test @MainActor
    func `Init vehicle search response is nil`() {
        let vm = SearchViewModel(searchResponse: makeSearchResponse(searchType: .address), apiService: nil)
        #expect(vm.vehicleSearchResponse == nil)
    }

    @Test @MainActor
    func `Init vehicle error is nil`() {
        let vm = SearchViewModel(searchResponse: makeSearchResponse(searchType: .address), apiService: nil)
        #expect(vm.vehicleError == nil)
    }

    // MARK: - selectVehicle / nil apiService

    @Test @MainActor
    func `Select vehicle nil api service vehicle search response remains nil`() async {
        let vm = SearchViewModel(searchResponse: makeSearchResponse(searchType: .vehicleID), apiService: nil)
        await vm.selectVehicle(vehicleID: vehicleID)
        #expect(vm.vehicleSearchResponse == nil)
    }

    @Test @MainActor
    func `Select vehicle nil api service sets vehicle error`() async {
        // Without an API service, the call would otherwise silently no-op. Surface the
        // misconfiguration through `vehicleError` so the existing error sink can present it.
        let vm = SearchViewModel(searchResponse: makeSearchResponse(searchType: .vehicleID), apiService: nil)
        await vm.selectVehicle(vehicleID: vehicleID)
        #expect(vm.vehicleError != nil)
    }

    // MARK: - selectVehicle / success

    @Test @MainActor
    func `Select vehicle success vehicle search response is set`() async {
        let vm = SearchViewModel(
            searchResponse: makeSearchResponse(searchType: .vehicleID, query: vehicleID),
            apiService: buildRESTService(dataLoader: makeSuccessLoader())
        )

        await vm.selectVehicle(vehicleID: vehicleID)

        #expect(vm.vehicleSearchResponse != nil)
        #expect(vm.vehicleError == nil)
    }

    @Test @MainActor
    func `Select vehicle success response contains single vehicle status result`() async {
        let vm = SearchViewModel(
            searchResponse: makeSearchResponse(searchType: .vehicleID, query: vehicleID),
            apiService: buildRESTService(dataLoader: makeSuccessLoader())
        )

        await vm.selectVehicle(vehicleID: vehicleID)

        #expect(vm.vehicleSearchResponse?.results.count == 1)
        #expect((vm.vehicleSearchResponse?.results.first as? VehicleStatus) != nil)
    }

    @Test @MainActor
    func `Select vehicle success preserves original request`() async {
        let vm = SearchViewModel(
            searchResponse: makeSearchResponse(searchType: .vehicleID, query: vehicleID),
            apiService: buildRESTService(dataLoader: makeSuccessLoader())
        )

        await vm.selectVehicle(vehicleID: vehicleID)

        #expect(vm.vehicleSearchResponse?.request.query == vehicleID)
        #expect(vm.vehicleSearchResponse?.request.searchType == .vehicleID)
    }

    // MARK: - selectVehicle / network error

    @Test @MainActor
    func `Select vehicle network error sets vehicle error`() async {
        let vm = SearchViewModel(
            searchResponse: makeSearchResponse(searchType: .vehicleID),
            apiService: buildRESTService(dataLoader: makeNetworkErrorLoader())
        )

        await vm.selectVehicle(vehicleID: vehicleID)

        #expect(vm.vehicleError != nil)
        #expect(vm.vehicleSearchResponse == nil)
    }

    // MARK: - selectVehicle / keyNotFound → noTripsAvailable

    @Test @MainActor
    func `Select vehicle key not found decoding sets no trips available error`() async {
        let vm = SearchViewModel(
            searchResponse: makeSearchResponse(searchType: .vehicleID),
            apiService: buildRESTService(dataLoader: makeKeyNotFoundLoader())
        )

        await vm.selectVehicle(vehicleID: vehicleID)

        #expect((vm.vehicleError as? SearchError) == .noTripsAvailable)
        #expect(vm.vehicleSearchResponse == nil)
    }

    // MARK: - selectVehicle / concurrent-call guard

    @Test @MainActor
    func `Select vehicle guard prevents concurrent calls`() async {
        let mockLoader = makeSuccessLoader()
        let countingLoader = CountingDataLoader(mockLoader)
        let config = APIServiceConfiguration(baseURL: baseURL, apiKey: apiKey, uuid: uuid, appVersion: appVersion, regionIdentifier: pugetSoundRegionIdentifier, surveyBaseURL: surveyBaseURL)
        let service = RESTAPIService(config, dataLoader: countingLoader)
        let vm = SearchViewModel(
            searchResponse: makeSearchResponse(searchType: .vehicleID, query: vehicleID),
            apiService: service
        )

        async let first: Void = vm.selectVehicle(vehicleID: vehicleID)
        async let second: Void = vm.selectVehicle(vehicleID: vehicleID)
        await first
        await second

        #expect(countingLoader.callCount == 1)
        #expect(vm.vehicleSearchResponse != nil)
    }

    // MARK: - selectVehicle / state transitions

    @Test @MainActor
    func `Select vehicle error then success vehicle error is cleared`() async {
        let loader = makeNetworkErrorLoader()
        let vm = SearchViewModel(
            searchResponse: makeSearchResponse(searchType: .vehicleID, query: vehicleID),
            apiService: buildRESTService(dataLoader: loader)
        )

        await vm.selectVehicle(vehicleID: vehicleID)
        #expect(vm.vehicleError != nil)

        loader.removeMappedResponses()
        loader.mock(URLString: vehicleURLString, with: Fixtures.loadData(file: "api_where_vehicle_1_4351.json"))

        await vm.selectVehicle(vehicleID: vehicleID)

        #expect(vm.vehicleError == nil)
        #expect(vm.vehicleSearchResponse != nil)
    }
}
