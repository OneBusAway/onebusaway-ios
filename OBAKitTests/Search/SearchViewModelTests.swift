//
//  SearchViewModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import MapKit
import Nimble
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try

class SearchViewModelTests: OBATestCase {

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

    @MainActor
    func test_subtitle_address_isQueryVerbatim() {
        let vm = SearchViewModel(searchResponse: makeSearchResponse(searchType: .address, query: "Seattle, WA"), apiService: nil)
        expect(vm.subtitle) == "Seattle, WA"
    }

    @MainActor
    func test_subtitle_route_prefixedWithRoute() {
        let vm = SearchViewModel(searchResponse: makeSearchResponse(searchType: .route, query: "44"), apiService: nil)
        expect(vm.subtitle) == "Route 44"
    }

    @MainActor
    func test_subtitle_stopNumber_prefixedWithStopNumber() {
        let vm = SearchViewModel(searchResponse: makeSearchResponse(searchType: .stopNumber, query: "1234"), apiService: nil)
        expect(vm.subtitle) == "Stop number 1234"
    }

    @MainActor
    func test_subtitle_vehicleID_prefixedWithVehicleID() {
        let vm = SearchViewModel(searchResponse: makeSearchResponse(searchType: .vehicleID, query: "XYZ"), apiService: nil)
        expect(vm.subtitle) == "Vehicle ID XYZ"
    }

    // MARK: - results

    @MainActor
    func test_results_matchesSearchResponseResults() throws {
        let stop = try Fixtures.loadSomeStops().first!
        let vm = SearchViewModel(searchResponse: makeSearchResponse(searchType: .stopNumber, results: [stop]), apiService: nil)
        expect(vm.results.count) == 1
        expect(vm.results.first as? Stop) === stop
    }

    // MARK: - response(substituting:)

    @MainActor
    func test_responseSubstituting_singleResultIsSubstitute() throws {
        let stops = try Fixtures.loadSomeStops()
        let vm = SearchViewModel(searchResponse: makeSearchResponse(searchType: .stopNumber, results: [stops[0]]), apiService: nil)

        let substituted = vm.response(substituting: stops[1])

        expect(substituted.results.count) == 1
        expect(substituted.results.first as? Stop) === stops[1]
    }

    @MainActor
    func test_responseSubstituting_preservesOriginalRequest() throws {
        let vm = SearchViewModel(searchResponse: makeSearchResponse(searchType: .route, query: "44"), apiService: nil)
        let substituted = vm.response(substituting: "anything")
        expect(substituted.request.query) == "44"
        expect(substituted.request.searchType) == .route
    }

    @MainActor
    func test_responseSubstituting_preservesBoundingRegion() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
        let searchResponse = SearchResponse(request: SearchRequest(query: "test", type: .address), results: [], boundingRegion: region, error: nil)
        let vm = SearchViewModel(searchResponse: searchResponse, apiService: nil)

        let substituted = vm.response(substituting: "anything")

        expect(substituted.boundingRegion).toNot(beNil())
        expect(substituted.boundingRegion?.center.latitude) == 47.6
        expect(substituted.boundingRegion?.center.longitude) == -122.3
    }

    @MainActor
    func test_responseSubstituting_preservesError() {
        let searchResponse = SearchResponse(request: SearchRequest(query: "test", type: .address), results: [], boundingRegion: nil, error: SearchError.noTripsAvailable)
        let vm = SearchViewModel(searchResponse: searchResponse, apiService: nil)

        let substituted = vm.response(substituting: "anything")

        expect(substituted.error as? SearchError) == .noTripsAvailable
    }

    // MARK: - Initial State

    @MainActor
    func test_init_vehicleSearchResponseIsNil() {
        let vm = SearchViewModel(searchResponse: makeSearchResponse(searchType: .address), apiService: nil)
        expect(vm.vehicleSearchResponse).to(beNil())
    }

    @MainActor
    func test_init_vehicleErrorIsNil() {
        let vm = SearchViewModel(searchResponse: makeSearchResponse(searchType: .address), apiService: nil)
        expect(vm.vehicleError).to(beNil())
    }

    // MARK: - selectVehicle / nil apiService

    @MainActor
    func test_selectVehicle_nilApiService_vehicleSearchResponseRemainsNil() async {
        let vm = SearchViewModel(searchResponse: makeSearchResponse(searchType: .vehicleID), apiService: nil)
        await vm.selectVehicle(vehicleID: vehicleID)
        expect(vm.vehicleSearchResponse).to(beNil())
    }

    @MainActor
    func test_selectVehicle_nilApiService_setsVehicleError() async {
        // Without an API service, the call would otherwise silently no-op. Surface the
        // misconfiguration through `vehicleError` so the existing error sink can present it.
        let vm = SearchViewModel(searchResponse: makeSearchResponse(searchType: .vehicleID), apiService: nil)
        await vm.selectVehicle(vehicleID: vehicleID)
        expect(vm.vehicleError).toNot(beNil())
    }

    // MARK: - selectVehicle / success

    @MainActor
    func test_selectVehicle_success_vehicleSearchResponseIsSet() async {
        let vm = SearchViewModel(
            searchResponse: makeSearchResponse(searchType: .vehicleID, query: vehicleID),
            apiService: buildRESTService(dataLoader: makeSuccessLoader())
        )

        await vm.selectVehicle(vehicleID: vehicleID)

        expect(vm.vehicleSearchResponse).toNot(beNil())
        expect(vm.vehicleError).to(beNil())
    }

    @MainActor
    func test_selectVehicle_success_responseContainsSingleVehicleStatusResult() async {
        let vm = SearchViewModel(
            searchResponse: makeSearchResponse(searchType: .vehicleID, query: vehicleID),
            apiService: buildRESTService(dataLoader: makeSuccessLoader())
        )

        await vm.selectVehicle(vehicleID: vehicleID)

        expect(vm.vehicleSearchResponse?.results.count) == 1
        expect(vm.vehicleSearchResponse?.results.first as? VehicleStatus).toNot(beNil())
    }

    @MainActor
    func test_selectVehicle_success_preservesOriginalRequest() async {
        let vm = SearchViewModel(
            searchResponse: makeSearchResponse(searchType: .vehicleID, query: vehicleID),
            apiService: buildRESTService(dataLoader: makeSuccessLoader())
        )

        await vm.selectVehicle(vehicleID: vehicleID)

        expect(vm.vehicleSearchResponse?.request.query) == vehicleID
        expect(vm.vehicleSearchResponse?.request.searchType) == .vehicleID
    }

    // MARK: - selectVehicle / network error

    @MainActor
    func test_selectVehicle_networkError_setsVehicleError() async {
        let vm = SearchViewModel(
            searchResponse: makeSearchResponse(searchType: .vehicleID),
            apiService: buildRESTService(dataLoader: makeNetworkErrorLoader())
        )

        await vm.selectVehicle(vehicleID: vehicleID)

        expect(vm.vehicleError).toNot(beNil())
        expect(vm.vehicleSearchResponse).to(beNil())
    }

    // MARK: - selectVehicle / keyNotFound → noTripsAvailable

    @MainActor
    func test_selectVehicle_keyNotFoundDecoding_setsNoTripsAvailableError() async {
        let vm = SearchViewModel(
            searchResponse: makeSearchResponse(searchType: .vehicleID),
            apiService: buildRESTService(dataLoader: makeKeyNotFoundLoader())
        )

        await vm.selectVehicle(vehicleID: vehicleID)

        expect(vm.vehicleError as? SearchError) == .noTripsAvailable
        expect(vm.vehicleSearchResponse).to(beNil())
    }

    // MARK: - selectVehicle / concurrent-call guard

    @MainActor
    func test_selectVehicle_guard_preventsConcurrentCalls() async {
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

        expect(countingLoader.callCount) == 1
        expect(vm.vehicleSearchResponse).toNot(beNil())
    }

    // MARK: - selectVehicle / state transitions

    @MainActor
    func test_selectVehicle_errorThenSuccess_vehicleErrorIsCleared() async {
        let loader = makeNetworkErrorLoader()
        let vm = SearchViewModel(
            searchResponse: makeSearchResponse(searchType: .vehicleID, query: vehicleID),
            apiService: buildRESTService(dataLoader: loader)
        )

        await vm.selectVehicle(vehicleID: vehicleID)
        expect(vm.vehicleError).toNot(beNil())

        loader.removeMappedResponses()
        loader.mock(URLString: vehicleURLString, with: Fixtures.loadData(file: "api_where_vehicle_1_4351.json"))

        await vm.selectVehicle(vehicleID: vehicleID)

        expect(vm.vehicleError).to(beNil())
        expect(vm.vehicleSearchResponse).toNot(beNil())
    }
}
