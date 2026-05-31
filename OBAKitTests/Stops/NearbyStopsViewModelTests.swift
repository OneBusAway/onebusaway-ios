//
//  NearbyStopsViewModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
import CoreLocation
@testable import OBAKit
@testable import OBAKitCore

class NearbyStopsViewModelTests: OBATestCase {

    let coordinate = TestData.seattleCoordinate
    let stopsURLString = "https://www.example.com/api/where/stops-for-location.json"

    // MARK: - Helpers

    func makeDataLoader(stubStops: Bool = false) -> MockDataLoader {
        let loader = MockDataLoader(testName: name)
        if stubStops {
            loader.mock(URLString: stopsURLString, with: Fixtures.loadData(file: "stops_for_location_seattle.json"))
        }
        return loader
    }

    func makeErrorLoader() -> MockDataLoader {
        let loader = MockDataLoader(testName: name)
        let error = NSError(domain: "NearbyStopsViewModelTests", code: 500, userInfo: nil)
        let response = MockDataResponse(data: nil, urlResponse: nil, error: error) { _ in true }
        loader.mock(response: response)
        return loader
    }

    // MARK: - Initial State

    @MainActor
    func test_init_stopsIsEmpty() {
        let viewModel = NearbyStopsViewModel(coordinate: coordinate, apiService: nil)
        expect(viewModel.stops).to(beEmpty())
    }

    @MainActor
    func test_init_isLoadingIsFalse() {
        let viewModel = NearbyStopsViewModel(coordinate: coordinate, apiService: nil)
        expect(viewModel.isLoading).to(beFalse())
    }

    @MainActor
    func test_init_operationErrorIsNil() {
        let viewModel = NearbyStopsViewModel(coordinate: coordinate, apiService: nil)
        expect(viewModel.operationError).to(beNil())
    }

    // MARK: - Guard: nil apiService

    @MainActor
    func test_loadStops_nilApiService_stopsRemainsEmpty() async {
        let viewModel = NearbyStopsViewModel(coordinate: coordinate, apiService: nil)
        await viewModel.loadStops()
        expect(viewModel.stops).to(beEmpty())
    }

    @MainActor
    func test_loadStops_nilApiService_isLoadingReturnsFalse() async {
        let viewModel = NearbyStopsViewModel(coordinate: coordinate, apiService: nil)
        await viewModel.loadStops()
        expect(viewModel.isLoading).to(beFalse())
    }

    @MainActor
    func test_loadStops_nilApiService_setsOperationError() async {
        // Without an API service, the screen would otherwise sit empty with no signal.
        // Surface the misconfiguration through `operationError` so the existing error
        // sink can present it.
        let viewModel = NearbyStopsViewModel(coordinate: coordinate, apiService: nil)
        await viewModel.loadStops()
        expect(viewModel.operationError).toNot(beNil())
    }

    // MARK: - Successful load

    @MainActor
    func test_loadStops_success_populatesStops() async {
        let service = buildRESTService(dataLoader: makeDataLoader(stubStops: true))
        let viewModel = NearbyStopsViewModel(coordinate: coordinate, apiService: service)

        await viewModel.loadStops()

        expect(viewModel.stops).toNot(beEmpty())
        expect(viewModel.operationError).to(beNil())
    }

    @MainActor
    func test_loadStops_success_isLoadingIsFalseAfterCompletion() async {
        let service = buildRESTService(dataLoader: makeDataLoader(stubStops: true))
        let viewModel = NearbyStopsViewModel(coordinate: coordinate, apiService: service)

        await viewModel.loadStops()

        expect(viewModel.isLoading).to(beFalse())
    }

    // MARK: - Failed load

    @MainActor
    func test_loadStops_failure_setsOperationError() async {
        let service = buildRESTService(dataLoader: makeErrorLoader())
        let viewModel = NearbyStopsViewModel(coordinate: coordinate, apiService: service)

        await viewModel.loadStops()

        expect(viewModel.operationError).toNot(beNil())
    }

    @MainActor
    func test_loadStops_failure_stopsRemainsEmpty() async {
        let service = buildRESTService(dataLoader: makeErrorLoader())
        let viewModel = NearbyStopsViewModel(coordinate: coordinate, apiService: service)

        await viewModel.loadStops()

        expect(viewModel.stops).to(beEmpty())
    }

    @MainActor
    func test_loadStops_failure_isLoadingIsFalseAfterCompletion() async {
        let service = buildRESTService(dataLoader: makeErrorLoader())
        let viewModel = NearbyStopsViewModel(coordinate: coordinate, apiService: service)

        await viewModel.loadStops()

        expect(viewModel.isLoading).to(beFalse())
    }

    // MARK: - Guard: prevents concurrent double-load

    @MainActor
    func test_loadStops_guard_preventsDoubleLoad() async {
        // CountingDataLoader yields before forwarding, giving the second concurrent
        // loadStops() a chance to run and see isLoading == true, so it returns early.
        let mockLoader = makeDataLoader(stubStops: true)
        let countingLoader = CountingDataLoader(mockLoader)
        let config = APIServiceConfiguration(baseURL: baseURL, apiKey: apiKey, uuid: uuid, appVersion: appVersion, regionIdentifier: pugetSoundRegionIdentifier, surveyBaseURL: surveyBaseURL)
        let service = RESTAPIService(config, dataLoader: countingLoader)
        let viewModel = NearbyStopsViewModel(coordinate: coordinate, apiService: service)

        async let first: Void = viewModel.loadStops()
        async let second: Void = viewModel.loadStops()
        await first
        await second

        expect(countingLoader.callCount) == 1
        expect(viewModel.stops).toNot(beEmpty())
        expect(viewModel.isLoading).to(beFalse())
    }
}
