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

        // Swap the weather mock for an error. removeMappedResponses() wipes *every*
        // stub — including the regions / agencies-with-coverage / agency-alerts ones
        // that the Application's async region resolver may still be hitting — so we
        // have to re-register them or in-flight requests will fatal on MockDataLoader.
        dataLoader.removeMappedResponses()
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        stubWeatherError(dataLoader: dataLoader)

        await viewModel.loadWeather()

        expect(viewModel.weather).to(beNil())
    }

    // MARK: - Map Type

    /// `toggleMapType()` flips the published `mapType` between `.standard` and `.hybrid`.
    /// Persistence to `MapRegionManager` is the VC's responsibility (via `$mapType` sink).
    @MainActor
    func test_toggleMapType_flipsAndPublishes() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = MapViewModel(application: app)
        expect(viewModel.mapType) == .standard

        var observed: [MapBaseType] = []
        let cancellable = viewModel.$mapType.sink { observed.append($0) }
        defer { cancellable.cancel() }

        viewModel.toggleMapType()
        expect(viewModel.mapType) == .hybrid

        viewModel.toggleMapType()
        expect(viewModel.mapType) == .standard

        // Initial value + two toggles.
        expect(observed) == [.standard, .hybrid, .standard]
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

    // MARK: - Survey Prompt

    /// Stubs the survey list endpoint with an empty payload so `fetchSurveys()` succeeds
    /// without surfacing an error.
    private func stubEmptySurveys(dataLoader: MockDataLoader) {
        let emptySurveys = #"{"surveys":[]}"#.data(using: .utf8)!
        dataLoader.mock(data: emptySurveys) { request in
            request.url?.path.contains("/surveys.json") ?? false
        }
    }

    /// When the gate is closed, `checkForSurveyPrompt` neither fetches nor emits.
    @MainActor
    func test_checkForSurveyPrompt_doesNothingWhenIneligible() async {
        let dataLoader = MockDataLoader(testName: name)
        stubEmptySurveys(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        userDefaults.set(false, forKey: "UserDataStore.isSurveyEnabled")

        let viewModel = MapViewModel(application: app)
        var received: [Survey] = []
        let cancellable = viewModel.surveyToPresent.sink { received.append($0) }
        defer { cancellable.cancel() }

        await viewModel.checkForSurveyPrompt()

        expect(received).to(beEmpty())
    }

    /// When eligible but no survey matches the map, `surveyToPresent` does not emit
    /// and the reminder is not advanced.
    @MainActor
    func test_checkForSurveyPrompt_doesNotEmitWhenNoMapSurvey() async {
        let dataLoader = MockDataLoader(testName: name)
        stubEmptySurveys(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        userDefaults.set(true, forKey: "UserDataStore.isSurveyEnabled")
        userDefaults.set(true, forKey: "UserDataStore.alwaysShowSurveysOnStops")

        let viewModel = MapViewModel(application: app)
        var received: [Survey] = []
        let cancellable = viewModel.surveyToPresent.sink { received.append($0) }
        defer { cancellable.cancel() }

        await viewModel.checkForSurveyPrompt()

        expect(received).to(beEmpty())
        expect(app.userDataStore.nextSurveyReminderDate).to(beNil())
    }

    /// `didPresentSurveyPrompt(_:)` advances the reminder and flips the session
    /// flag so a subsequent `checkForSurveyPrompt` in the same session no-ops.
    /// Verifies the intent contract directly rather than going through the
    /// `findSurveyForMap` integration path (orchestrator-level happy paths
    /// cover the find + submit sequence).
    @MainActor
    func test_didPresentSurveyPrompt_advancesReminderAndFlipsSession() async {
        let dataLoader = MockDataLoader(testName: name)
        stubEmptySurveys(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = MapViewModel(application: app)

        let hero = SurveyQuestion(id: 1, position: 1, required: false, content: QuestionContent(labelText: "q", type: .text))
        let survey = Survey(
            id: 7100, name: "Test", createdAt: Date(), updatedAt: Date(),
            showOnMap: true, showOnStops: false,
            startDate: nil, endDate: nil,
            visibleStopsList: nil, visibleRoutesList: nil,
            allowsMultipleResponses: false, alwaysVisible: true,
            study: Study(id: 1, name: "S", description: nil),
            questions: [hero]
        )

        expect(app.userDataStore.nextSurveyReminderDate).to(beNil())
        viewModel.didPresentSurveyPrompt(survey)
        expect(app.userDataStore.nextSurveyReminderDate).toNot(beNil())

        // A second `didPresentSurveyPrompt` in the same session is idempotent.
        let before = app.userDataStore.nextSurveyReminderDate
        viewModel.didPresentSurveyPrompt(survey)
        expect(app.userDataStore.nextSurveyReminderDate) == before
    }

}
