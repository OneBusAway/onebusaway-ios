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

    override func setUp() async throws {
        try await super.setUp()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    override func tearDown() async throws {
        try await super.tearDown()
        queue.cancelAllOperations()
    }

    // MARK: - Application Builder

    /// Builds an `Application` locked to Puget Sound so the region (and thus the obaco
    /// sidecar base URL the weather call resolves against) is deterministic.
    /// Pass `bundledRegionsFixture: "regions-puget-sound-no-sidecar.json"` to swap the
    /// bundled regions file for one whose Puget Sound entry has no `sidecarBaseURL` —
    /// keeps `application.obacoService` nil and `features.obaco == .off`.
    private func createApplication(
        dataLoader: MockDataLoader,
        bundledRegionsFixture: String? = nil,
        accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy
    ) -> Application {
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        let locManager = MockAuthorizedLocationManager(
            updateLocation: TestData.mockSeattleLocation,
            updateHeading: TestData.mockHeading
        )
        locManager.overrideAccuracyAuthorization = accuracyAuthorization
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
            bundledRegionsFilePath: bundledRegionsFixture.map { Fixtures.path(to: $0) } ?? bundledRegionsPath,
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

    /// A successful weather fetch publishes a non-nil display.
    @MainActor
    func test_loadWeather_successPublishesDisplay() async {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        stubWeatherSuccess(dataLoader: dataLoader)

        let viewModel = MapViewModel(application: app)
        expect(viewModel.weatherDisplay).to(beNil())

        await viewModel.loadWeather()

        expect(viewModel.weatherDisplay).toNot(beNil())
        expect(viewModel.weatherDisplay?.header.regionName) == "Puget Sound"
    }

    /// A transient weather fetch failure must NOT clear `weatherDisplay` —
    /// the floating button would otherwise vanish on every network blip even
    /// when a perfectly good last-known forecast exists. First loads
    /// successfully, then errors, then asserts the last forecast survives.
    @MainActor
    func test_loadWeather_errorKeepsLastForecast() async {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        stubWeatherSuccess(dataLoader: dataLoader)

        let viewModel = MapViewModel(application: app)
        await viewModel.loadWeather()
        let firstDisplay = viewModel.weatherDisplay
        expect(firstDisplay).toNot(beNil())

        // Swap the weather mock for an error. The swap must be atomic: the
        // Application's background tasks (regions refresh, agency alerts) may have
        // requests in flight, and a clear-then-re-mock sequence leaves a window where
        // an unmatched request takes down the suite via MockDataLoader's fatalError.
        dataLoader.replaceMappedResponses { staging in
            stubRegions(dataLoader: staging)
            stubAgenciesWithCoverage(dataLoader: staging, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
            Fixtures.stubAllAgencyAlerts(dataLoader: staging)
            stubWeatherError(dataLoader: staging)
        }

        await viewModel.loadWeather()

        // Same instance — error path didn't overwrite or clear.
        expect(viewModel.weatherDisplay) == firstDisplay
    }

    /// When `application.obacoService` is nil (region retired the sidecar, or it
    /// never finished spinning up), the floating button hides
    /// (`isWeatherFeatureAvailable == false`) and the guard branch of
    /// `loadWeather()` leaves `weatherDisplay` nil. This is the configuration-shaped
    /// inversion of `test_loadWeather_errorKeepsLastForecast` — out-of-region SHOULD
    /// drop the button, transient failures SHOULD NOT.
    @MainActor
    func test_loadWeather_clearsDisplayWhenObacoUnavailable() async {
        // `RegionsService` prefers disk-stored regions over the bundled file,
        // and prior runs in the same simulator can leave a stored copy with a
        // sidecar URL. Wipe the shared on-disk default-regions file so the
        // no-sidecar bundled fixture is what feeds `currentRegion`.
        let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        if let appSupport {
            try? FileManager.default.removeItem(
                at: appSupport.appendingPathComponent("Regions/default-regions.json")
            )
        }

        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(
            dataLoader: dataLoader,
            bundledRegionsFixture: "regions-puget-sound-no-sidecar.json"
        )

        // Precondition: the bundled fixture has no `sidecarBaseURL`, so the
        // synchronous Obaco refresh during `Application` init leaves
        // `obacoService` nil and the feature gate stays closed.
        expect(app.obacoService).to(beNil())
        expect(app.features.obaco).toNot(equal(.running))

        let viewModel = MapViewModel(application: app)
        expect(viewModel.isWeatherFeatureAvailable) == false
        expect(viewModel.weatherDisplay).to(beNil())

        await viewModel.loadWeather()

        // Guard path took the early return; weatherDisplay stays nil.
        expect(viewModel.weatherDisplay).to(beNil())
    }

    // MARK: - Map Type

    /// `toggleMapType()` flips the published `mapType` between `.standard` and `.hybrid`
    /// and persists the selection through `MapRegionManager` so a later launch
    /// (or the UIKit path) reads the same value.
    @MainActor
    func test_toggleMapType_flipsAndPublishesAndPersists() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = MapViewModel(application: app)
        expect(viewModel.mapType) == .standard

        var observed: [MapBaseType] = []
        let cancellable = viewModel.$mapType.sink { observed.append($0) }
        defer { cancellable.cancel() }

        viewModel.toggleMapType()
        expect(viewModel.mapType) == .hybrid
        expect(app.mapRegionManager.userSelectedMapType) == .hybrid

        viewModel.toggleMapType()
        expect(viewModel.mapType) == .standard
        expect(app.mapRegionManager.userSelectedMapType) == .mutedStandard

        // Initial value + two toggles.
        expect(observed) == [.standard, .hybrid, .standard]
    }

    /// An external mutation of `MapRegionManager.userSelectedMapType`
    /// propagates back into `MapViewModel.mapType`. Covers the case where the
    /// UIKit path (or a future consumer) changes the persisted value while
    /// the SwiftUI root is mounted.
    @MainActor
    func test_mapType_syncsFromExternalMapRegionManagerChange() async {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = MapViewModel(application: app)
        expect(viewModel.mapType) == .standard

        // External mutation — bypasses `toggleMapType()` entirely, simulating
        // the UIKit path or an out-of-VM defaults edit.
        app.mapRegionManager.userSelectedMapType = .hybrid

        // `UserDefaults.didChangeNotification` fan-out is `receive(on: main)`,
        // so give the runloop a few hops to deliver.
        for _ in 0..<5 { await Task.yield() }

        expect(viewModel.mapType) == .hybrid
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

    /// Stubs the survey list endpoint with a schema-valid empty `StudyResponse`
    /// so `fetchSurveys()` succeeds via "no matching survey" rather than decode
    /// failure — the "doesNotEmit" assertions otherwise pass for the wrong
    /// reason.
    private func stubEmptySurveys(dataLoader: MockDataLoader) {
        let studyResponse = StudyResponse(
            surveys: [],
            region: SurveyRegion(id: 1, name: "Test")
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // swiftlint:disable:next force_try
        let data = try! encoder.encode(studyResponse)
        dataLoader.mock(data: data) { request in
            request.url?.path.contains("/surveys.json") ?? false
        }
    }

    /// Stubs the survey list endpoint with a single always-visible map survey
    /// (id 7100) so `findSurveyForMap()` resolves non-nil.
    private func stubMapSurvey(dataLoader: MockDataLoader) {
        let hero = SurveyQuestion(
            id: 1, position: 1, required: false,
            content: QuestionContent(labelText: "q", type: .text)
        )
        let survey = Survey(
            id: 7100, name: "Map Test",
            createdAt: Date(), updatedAt: Date(),
            showOnMap: true, showOnStops: false,
            startDate: nil, endDate: nil,
            visibleStopsList: nil, visibleRoutesList: nil,
            allowsMultipleResponses: false, alwaysVisible: true,
            study: Study(id: 1, name: "S", description: nil),
            questions: [hero]
        )
        let studyResponse = StudyResponse(
            surveys: [survey],
            region: SurveyRegion(id: 1, name: "Test")
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // swiftlint:disable:next force_try
        let data = try! encoder.encode(studyResponse)
        dataLoader.mock(data: data) { request in
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

    /// `didPresentSurveyPrompt(_:presented:)` with `presented == true` advances the
    /// reminder. Verifies the intent contract directly rather than going through the
    /// `findSurveyForMap` integration path (orchestrator-level happy paths cover
    /// the find + submit sequence).
    @MainActor
    func test_didPresentSurveyPrompt_advancesReminderOnPresented() async {
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
        viewModel.didPresentSurveyPrompt(survey, presented: true)
        expect(app.userDataStore.nextSurveyReminderDate).toNot(beNil())
    }

    /// After `presented == false`, the session flag rolls back so a second
    /// `checkForSurveyPrompt()` can re-emit on `surveyToPresent`. Without the
    /// rollback the prompt would be lost for the rest of the session.
    @MainActor
    func test_checkForSurveyPrompt_reEmitsAfterPresentedFalseRollback() async {
        let dataLoader = MockDataLoader(testName: name)
        stubMapSurvey(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        userDefaults.set(true, forKey: "UserDataStore.isSurveyEnabled")
        userDefaults.set(true, forKey: "UserDataStore.alwaysShowSurveysOnStops")

        let viewModel = MapViewModel(application: app)
        var received: [Survey] = []
        let cancellable = viewModel.surveyToPresent.sink { received.append($0) }
        defer { cancellable.cancel() }

        await viewModel.checkForSurveyPrompt()
        expect(received.count) == 1

        // Simulate the presenter dropping the survey.
        viewModel.didPresentSurveyPrompt(received[0], presented: false)
        // Reminder must NOT have advanced on the rollback path.
        expect(app.userDataStore.nextSurveyReminderDate).to(beNil())

        await viewModel.checkForSurveyPrompt()
        expect(received.count) == 2
    }

    /// `didPresentSurveyPrompt(_:presented:)` with `presented == false` does not
    /// advance the reminder — that path is the rollback for "presenter went away
    /// between emission and present."
    @MainActor
    func test_didPresentSurveyPrompt_doesNotAdvanceReminderWhenNotPresented() async {
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
        viewModel.didPresentSurveyPrompt(survey, presented: false)
        expect(app.userDataStore.nextSurveyReminderDate).to(beNil())
    }

    /// Stubs the survey list endpoint to error so `fetchSurveys()` records
    /// `surveyService.lastError` instead of clearing it.
    private func stubSurveysError(dataLoader: MockDataLoader) {
        let response = MockDataResponse(
            data: nil,
            urlResponse: nil,
            error: URLError(.badServerResponse)
        ) { request in
            request.url?.path.contains("/surveys.json") ?? false
        }
        dataLoader.mock(response: response)
    }

    /// Concurrent `checkForSurveyPrompt()` calls must emit exactly once. The VM flips
    /// `hasShownSurveyThisSession = true` synchronously before `send` (after the awaited
    /// refresh) so a second call racing through the post-await re-check sees the flag set
    /// and bails. This is the direct analogue of the StopViewModel re-entrancy test.
    @MainActor
    func test_checkForSurveyPrompt_concurrentCallsEmitOnce() async {
        let dataLoader = MockDataLoader(testName: name)
        stubMapSurvey(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        userDefaults.set(true, forKey: "UserDataStore.isSurveyEnabled")
        userDefaults.set(true, forKey: "UserDataStore.alwaysShowSurveysOnStops")

        let viewModel = MapViewModel(application: app)
        var received: [Survey] = []
        let cancellable = viewModel.surveyToPresent.sink { received.append($0) }
        defer { cancellable.cancel() }

        async let a: Void = viewModel.checkForSurveyPrompt()
        async let b: Void = viewModel.checkForSurveyPrompt()
        _ = await (a, b)

        expect(received.count) == 1
    }

    /// When the refresh fails, `surveyToPresent` must not emit even if the
    /// cached survey list would otherwise resolve `findSurveyForMap()`.
    /// Prevents prompting off a stale cached survey after a transient network
    /// failure.
    @MainActor
    func test_checkForSurveyPrompt_doesNotEmitWhenRefreshFailed() async {
        let dataLoader = MockDataLoader(testName: name)
        stubSurveysError(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        userDefaults.set(true, forKey: "UserDataStore.isSurveyEnabled")
        userDefaults.set(true, forKey: "UserDataStore.alwaysShowSurveysOnStops")

        let viewModel = MapViewModel(application: app)
        var received: [Survey] = []
        let cancellable = viewModel.surveyToPresent.sink { received.append($0) }
        defer { cancellable.cancel() }

        await viewModel.checkForSurveyPrompt()

        // No emission, no reminder advance. Pairs with the orchestrator-level
        // `test_lastError_reflectsUnderlyingService_afterFetchFailure` which
        // verifies that the orchestrator's `lastError` accessor (the gate's
        // input) actually surfaces on a failed refresh.
        expect(received).to(beEmpty())
        expect(app.userDataStore.nextSurveyReminderDate).to(beNil())
    }

    // MARK: - Zoom Helpers

    /// The zoom-in-for-stops span is a fixed constant shared with `MapStatusPill`
    /// / `MapViewController.didTapZoomInForStops` so both surfaces zoom to the
    /// same target when the user taps "Zoom in for stops."
    @MainActor
    func test_zoomInForStopsSpan_isSharedConstant() {
        expect(MapViewModel.zoomInForStopsSpan) == 0.01
    }

    /// Full-accuracy authorization returns a tight zoom (17); reduced-accuracy
    /// backs off to a coarser zoom (11) so the ~1km fuzz cell fits in view.
    /// Mirrors the branch in `MapViewController.centerMapOnUserLocation`.
    @MainActor
    func test_zoomLevelForCurrentLocation_fullAccuracyReturns17() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = MapViewModel(application: app)

        expect(app.locationService.accuracyAuthorization) == .fullAccuracy
        expect(viewModel.zoomLevelForCurrentLocation()) == 17
    }

    /// Reduced accuracy backs off to 11 so the ~1km fuzz cell fits comfortably
    /// on screen. Companion to `_fullAccuracyReturns17` — both branches must
    /// stay covered or a future refactor could silently change one.
    @MainActor
    func test_zoomLevelForCurrentLocation_reducedAccuracyReturns11() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader, accuracyAuthorization: .reducedAccuracy)
        let viewModel = MapViewModel(application: app)

        expect(app.locationService.accuracyAuthorization) == .reducedAccuracy
        expect(viewModel.zoomLevelForCurrentLocation()) == 11
    }

    // MARK: - TopPillState

    /// Zoom warning wins over permission state so tapping the pill still routes
    /// to the zoom-in action even if the user is also on reduced accuracy.
    /// Mirrors `MapStatusView.configure(for:zoomInStatus:)` where `zoomInStatus`
    /// overwrites the base state.
    @MainActor
    func test_topPillState_zoomWarningWinsOverPermission() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = MapViewModel(application: app)

        viewModel.updateZoomWarning(true)
        expect(viewModel.topPillState) == .zoomInForStops
    }

    /// With no zoom warning and full permission, the pill is hidden.
    @MainActor
    func test_topPillState_hiddenWhenAuthorizedAndZoomed() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = MapViewModel(application: app)

        viewModel.updateZoomWarning(false)
        expect(viewModel.topPillState) == .hidden
    }

    /// A `.denied` auth status maps to `.locationServicesOff` when no zoom warning is active.
    @MainActor
    func test_topPillState_deniedMapsToLocationServicesOff() async {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = MapViewModel(application: app)

        viewModel.locationService(app.locationService, authorizationStatusChanged: .denied)
        for _ in 0..<5 { await Task.yield() }

        expect(viewModel.topPillState) == .locationServicesOff
    }

    /// A `.restricted` auth status maps to `.locationServicesUnavailable`, a
    /// visible-but-non-actionable pill. A restricted (MDM/parental) user can't
    /// lift the restriction in Settings, so folding it into `.locationServicesOff`
    /// — which offers a "Turn On in Settings" prompt — would be a dead end.
    @MainActor
    func test_topPillState_restrictedMapsToLocationServicesUnavailable() async {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = MapViewModel(application: app)

        viewModel.locationService(app.locationService, authorizationStatusChanged: .restricted)
        for _ in 0..<5 { await Task.yield() }

        expect(viewModel.topPillState) == .locationServicesUnavailable
    }

    /// A `.notDetermined` auth status maps to `.notDetermined` when no zoom warning is active.
    @MainActor
    func test_topPillState_notDeterminedMapsToPill() async {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = MapViewModel(application: app)

        viewModel.locationService(app.locationService, authorizationStatusChanged: .notDetermined)
        for _ in 0..<5 { await Task.yield() }

        expect(viewModel.topPillState) == .notDetermined
    }

    /// `.authorizedWhenInUse` + `.reducedAccuracy` surfaces the imprecise-location
    /// pill so the user can raise accuracy without leaving the map. Mirrors the
    /// branch in `MapStatusView.state(for:)`.
    @MainActor
    func test_topPillState_authorizedReducedAccuracyMapsToImpreciseLocation() async {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader, accuracyAuthorization: .reducedAccuracy)
        let viewModel = MapViewModel(application: app)

        viewModel.locationService(app.locationService, authorizationStatusChanged: .authorizedWhenInUse)
        for _ in 0..<5 { await Task.yield() }

        expect(viewModel.topPillState) == .impreciseLocation
    }

    /// Granting full accuracy while the coarse status stays `.authorizedWhenInUse`
    /// (the "Allow Once" path) clears the imprecise-location pill. Guards the
    /// regression where `topPillState` read accuracy live from `locationService`
    /// and never re-evaluated on an accuracy-only change, leaving the pill stuck.
    @MainActor
    func test_topPillState_accuracyElevationClearsImprecisePill() async {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader, accuracyAuthorization: .reducedAccuracy)
        let viewModel = MapViewModel(application: app)

        viewModel.locationService(app.locationService, authorizationStatusChanged: .authorizedWhenInUse)
        for _ in 0..<5 { await Task.yield() }
        expect(viewModel.topPillState) == .impreciseLocation

        // Accuracy elevates to full without the coarse status changing.
        viewModel.locationService(app.locationService, accuracyAuthorizationChanged: .fullAccuracy)
        for _ in 0..<5 { await Task.yield() }
        expect(viewModel.topPillState) == .hidden
    }

}
