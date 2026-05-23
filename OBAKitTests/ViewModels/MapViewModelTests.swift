//
//  MapViewModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
import Combine
import CoreLocation
import MapKit
@testable import OBAKit
@testable import OBAKitCore

/// Tests for `MapViewModel`: weather loading (success + error), map-type toggle
/// persistence + publishing, and the location-authorization delegate callback.
class MapViewModelTests: OBATestCase {
    var queue: OperationQueue!

    override func setUp() {
        super.setUp()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    override func tearDown() {
        super.tearDown()
        queue.cancelAllOperations()
    }

    // MARK: - Application Builder

    /// Builds an `Application` locked to Puget Sound so the region (and thus the obaco
    /// sidecar base URL the weather call resolves against) is deterministic.
    private func createApplication(dataLoader: MockDataLoader) -> Application {
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        let locManager = MockAuthorizedLocationManager(
            updateLocation: TestData.mockSeattleLocation,
            updateHeading: TestData.mockHeading
        )
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        locationService.startUpdates()

        let config = AppConfig(
            regionsBaseURL: regionsURL,
            apiKey: apiKey,
            appVersion: appVersion,
            userDefaults: userDefaults,
            analytics: AnalyticsMock(),
            queue: queue,
            locationService: locationService,
            bundledRegionsFilePath: bundledRegionsPath,
            regionsAPIPath: regionsAPIPath,
            dataLoader: dataLoader,
            fixedRegionName: Fixtures.pugetSoundRegion.name
        )

        return Application(config: config)
    }

    /// Stubs the obaco weather endpoint with the real fixture payload.
    private func stubWeatherSuccess(dataLoader: MockDataLoader) {
        let data = Fixtures.loadData(file: "pugetsound-weather.json")
        dataLoader.mock(data: data) { request in
            request.url?.path.contains("/weather.json") ?? false
        }
    }

    /// Stubs the obaco weather endpoint to throw, exercising the `loadWeather()` catch branch.
    private func stubWeatherError(dataLoader: MockDataLoader) {
        let response = MockDataResponse(
            data: nil,
            urlResponse: nil,
            error: URLError(.badServerResponse)
        ) { request in
            request.url?.path.contains("/weather.json") ?? false
        }
        dataLoader.mock(response: response)
    }

    // MARK: - Weather

    /// A successful weather fetch publishes a non-nil forecast.
    @MainActor
    func test_loadWeather_successPublishesForecast() async {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        stubWeatherSuccess(dataLoader: dataLoader)

        let viewModel = MapViewModel(application: app)
        expect(viewModel.weather).to(beNil())

        await viewModel.loadWeather()

        expect(viewModel.weather).toNot(beNil())
        expect(viewModel.weather?.regionName) == "Puget Sound"
    }

    /// A weather fetch that errors must clear `weather` (back to nil) and not crash.
    /// First loads successfully so we can prove the error path actually clears the value.
    @MainActor
    func test_loadWeather_errorClearsForecast() async {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        stubWeatherSuccess(dataLoader: dataLoader)

        let viewModel = MapViewModel(application: app)
        await viewModel.loadWeather()
        expect(viewModel.weather).toNot(beNil())

        // Swap the weather mock for an error. getWeather() only hits the weather URL, so
        // dropping the other mocks is safe for this second load.
        dataLoader.removeMappedResponses()
        stubWeatherError(dataLoader: dataLoader)

        await viewModel.loadWeather()

        expect(viewModel.weather).to(beNil())
    }

    // MARK: - Map Type

    /// `toggleMapType()` flips the published `mapType` and persists the selection through
    /// `MapRegionManager` (which writes to UserDefaults).
    @MainActor
    func test_toggleMapType_persistsAndPublishes() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = MapViewModel(application: app)
        expect(viewModel.mapType) == .mutedStandard  // registered default

        var observed: [MKMapType] = []
        let cancellable = viewModel.$mapType.sink { observed.append($0) }
        defer { cancellable.cancel() }

        viewModel.toggleMapType()
        expect(viewModel.mapType) == .hybrid
        expect(app.mapRegionManager.userSelectedMapType) == .hybrid

        viewModel.toggleMapType()
        expect(viewModel.mapType) == .mutedStandard
        expect(app.mapRegionManager.userSelectedMapType) == .mutedStandard

        // Initial value + two toggles.
        expect(observed) == [.mutedStandard, .hybrid, .mutedStandard]
    }

    // MARK: - Location Authorization

    /// The `LocationServiceDelegate` callback updates the published `locationAuthStatus`.
    @MainActor
    func test_locationAuthStatus_updatesViaDelegateCallback() async {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = MapViewModel(application: app)
        expect(viewModel.locationAuthStatus) == .authorizedWhenInUse  // from the mock manager

        viewModel.locationService(app.locationService, authorizationStatusChanged: .denied)

        // The callback hops to the main actor via `Task { @MainActor in ... }`.
        for _ in 0..<5 { await Task.yield() }

        expect(viewModel.locationAuthStatus) == .denied
    }
}
