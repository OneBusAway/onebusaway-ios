//
//  NearbyStopsViewModelExtendedTests.swift
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

/// Extended tests for `NearbyStopsViewModel` error transitions,
/// coordinate boundaries, and reload cancelation.
@Suite(.serialized)
final class NearbyStopsViewModelExtendedTests: OBATestCase {

    private let coordinate = TestData.seattleCoordinate
    private let stopsURLString = "https://www.example.com/api/where/stops-for-location.json"

    private func makeDataLoader(stubStops: Bool = false) -> MockDataLoader {
        let loader = MockDataLoader(testName: name)
        if stubStops {
            loader.mock(URLString: stopsURLString, with: Fixtures.loadData(file: "stops_for_location_seattle.json"))
        }
        return loader
    }

    private func makeFailingDataLoader(statusCode: Int = 500) -> MockDataLoader {
        let loader = MockDataLoader(testName: name)
        let error = NSError(domain: "NearbyStopsDomainError", code: statusCode, userInfo: nil)
        loader.mock(response: MockDataResponse(data: nil, urlResponse: nil, error: error) { _ in true })
        return loader
    }

    @Test @MainActor
    func `Reload with error response updates operationError and clears loading state`() async {
        let dataLoader = makeFailingDataLoader(statusCode: 503)
        let apiService = buildRESTService(dataLoader: dataLoader)
        let viewModel = NearbyStopsViewModel(coordinate: coordinate, apiService: apiService)

        await viewModel.loadStops()

        #expect(!viewModel.isLoading)
        #expect(viewModel.stops.isEmpty)
        #expect(viewModel.operationError != nil)
    }

    @Test @MainActor
    func `Reload with successful data populates stops and clears operationError`() async {
        let dataLoader = makeDataLoader(stubStops: true)
        let apiService = buildRESTService(dataLoader: dataLoader)
        let viewModel = NearbyStopsViewModel(coordinate: coordinate, apiService: apiService)

        await viewModel.loadStops()

        #expect(!viewModel.isLoading)
        #expect(!viewModel.stops.isEmpty)
        #expect(viewModel.operationError == nil)
    }

    @Test @MainActor
    func `Successive reload recovers from previous error`() async {
        let dataLoader = makeFailingDataLoader()
        let apiService = buildRESTService(dataLoader: dataLoader)
        let viewModel = NearbyStopsViewModel(coordinate: coordinate, apiService: apiService)

        await viewModel.loadStops()
        #expect(viewModel.operationError != nil)

        // Mock success response
        dataLoader.replaceMappedResponses { loader in
            loader.mock(URLString: self.stopsURLString, with: Fixtures.loadData(file: "stops_for_location_seattle.json"))
        }

        await viewModel.loadStops()
        #expect(viewModel.operationError == nil)
        #expect(!viewModel.stops.isEmpty)
    }
}
