//
//  NearbyStopsViewModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import CoreLocation
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class NearbyStopsViewModelTests: OBATestCase {

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

    @Test @MainActor
    func `Init stops is empty`() {
        let viewModel = NearbyStopsViewModel(coordinate: coordinate, apiService: nil)
        #expect(viewModel.stops.isEmpty)
    }

    @Test @MainActor
    func `Init is loading is false`() {
        let viewModel = NearbyStopsViewModel(coordinate: coordinate, apiService: nil)
        #expect(!viewModel.isLoading)
    }

    @Test @MainActor
    func `Init operation error is nil`() {
        let viewModel = NearbyStopsViewModel(coordinate: coordinate, apiService: nil)
        #expect(viewModel.operationError == nil)
    }

    // MARK: - Guard: nil apiService

    @Test @MainActor
    func `Load stops nil api service stops remains empty`() async {
        let viewModel = NearbyStopsViewModel(coordinate: coordinate, apiService: nil)
        await viewModel.loadStops()
        #expect(viewModel.stops.isEmpty)
    }

    @Test @MainActor
    func `Load stops nil api service is loading returns false`() async {
        let viewModel = NearbyStopsViewModel(coordinate: coordinate, apiService: nil)
        await viewModel.loadStops()
        #expect(!viewModel.isLoading)
    }

    @Test @MainActor
    func `Load stops nil api service sets operation error`() async {
        // Without an API service, the screen would otherwise sit empty with no signal.
        // Surface the misconfiguration through `operationError` so the existing error
        // sink can present it.
        let viewModel = NearbyStopsViewModel(coordinate: coordinate, apiService: nil)
        await viewModel.loadStops()
        #expect(viewModel.operationError != nil)
    }

    // MARK: - Successful load

    @Test @MainActor
    func `Load stops success populates stops`() async {
        let service = buildRESTService(dataLoader: makeDataLoader(stubStops: true))
        let viewModel = NearbyStopsViewModel(coordinate: coordinate, apiService: service)

        await viewModel.loadStops()

        #expect(!viewModel.stops.isEmpty)
        #expect(viewModel.operationError == nil)
    }

    @Test @MainActor
    func `Load stops success is loading is false after completion`() async {
        let service = buildRESTService(dataLoader: makeDataLoader(stubStops: true))
        let viewModel = NearbyStopsViewModel(coordinate: coordinate, apiService: service)

        await viewModel.loadStops()

        #expect(!viewModel.isLoading)
    }

    // MARK: - Failed load

    @Test @MainActor
    func `Load stops failure sets operation error`() async {
        let service = buildRESTService(dataLoader: makeErrorLoader())
        let viewModel = NearbyStopsViewModel(coordinate: coordinate, apiService: service)

        await viewModel.loadStops()

        #expect(viewModel.operationError != nil)
    }

    @Test @MainActor
    func `Load stops failure stops remains empty`() async {
        let service = buildRESTService(dataLoader: makeErrorLoader())
        let viewModel = NearbyStopsViewModel(coordinate: coordinate, apiService: service)

        await viewModel.loadStops()

        #expect(viewModel.stops.isEmpty)
    }

    @Test @MainActor
    func `Load stops failure is loading is false after completion`() async {
        let service = buildRESTService(dataLoader: makeErrorLoader())
        let viewModel = NearbyStopsViewModel(coordinate: coordinate, apiService: service)

        await viewModel.loadStops()

        #expect(!viewModel.isLoading)
    }

    // MARK: - Guard: prevents concurrent double-load

    @Test @MainActor
    func `Load stops guard prevents double load`() async {
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

        #expect(countingLoader.callCount == 1)
        #expect(!viewModel.stops.isEmpty)
        #expect(!viewModel.isLoading)
    }
}
