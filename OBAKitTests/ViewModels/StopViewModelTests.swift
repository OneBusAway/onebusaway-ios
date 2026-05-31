//
//  StopViewModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
import Combine
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast force_try

/// Tests for `StopViewModel`. Regression tests for review issues #1, #2, and #8.
class StopViewModelTests: OBATestCase {
    let testStopID = "1_TEST"
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

    /// Builds an `Application` whose REST API service routes through the supplied `MockDataLoader`.
    /// Locks the current region to Puget Sound so the API base URL is deterministic.
    private func createApplication(dataLoader: MockDataLoader, analytics: AnalyticsMock) -> Application {
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        stubArrivalsAndDepartures(dataLoader: dataLoader)
        stubSurveys(dataLoader: dataLoader)

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
            analytics: analytics,
            queue: queue,
            locationService: locationService,
            bundledRegionsFilePath: bundledRegionsPath,
            regionsAPIPath: regionsAPIPath,
            dataLoader: dataLoader,
            fixedRegionName: Fixtures.pugetSoundRegion.name
        )

        return Application(config: config)
    }

    /// Stubs every `arrivals-and-departures-for-stop` call with an empty-arrivals payload.
    /// The matcher is path-based, so the same stub serves every minutesAfter value the VM walks through.
    private func stubArrivalsAndDepartures(dataLoader: MockDataLoader) {
        let data = Fixtures.loadData(file: "arrivals_and_departures_empty.json")
        dataLoader.mock(data: data) { request in
            request.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false
        }
    }

    /// Stubs the surveys endpoint with an empty-list payload so `refreshSurveys()` doesn't fatal-error.
    private func stubSurveys(dataLoader: MockDataLoader) {
        let emptySurveys = #"{"surveys":[],"region":{"id":1,"name":"Puget Sound"}}"#.data(using: .utf8)!
        dataLoader.mock(data: emptySurveys) { request in
            request.url?.path.contains("/surveys.json") ?? false
        }
    }

    // MARK: - Auto-Extend / Cap (issues #2, #8)

    /// Empty results should drive the auto-extend recursion all the way to the 720-minute cap,
    /// monotonically increase `minutesAfter`, and flip `isLoadMoreExhausted` to true.
    @MainActor
    func test_autoExtend_walksToCapAndFlipsExhausted() async {
        let dataLoader = MockDataLoader(testName: name)
        let analytics = AnalyticsMock()
        let app = createApplication(dataLoader: dataLoader, analytics: analytics)

        let viewModel = StopViewModel(application: app, stopID: testStopID)

        var observed: [UInt] = []
        let cancellable = viewModel.$minutesAfter.sink { observed.append($0) }
        defer { cancellable.cancel() }

        await viewModel.refresh()

        // Strictly increasing trajectory ending at the cap.
        expect(observed).to(equal(observed.sorted()))
        expect(observed.last) == 720
        expect(viewModel.minutesAfter) == 720
        expect(viewModel.isLoadMoreExhausted).to(beTrue())

        // Verify each hop made strict forward progress (no duplicates after the initial value).
        let distinctAscending = Array(NSOrderedSet(array: observed)) as! [UInt]
        expect(distinctAscending.count) == observed.count
    }

    // MARK: - Analytics fires once (issue #1)

    /// `reportStopViewed` must fire exactly once per VM lifetime, even when refresh() is
    /// invoked many times by the auto-extend chain or by the user.
    @MainActor
    func test_analyticsFiresExactlyOnceAcrossRefreshes() async {
        let dataLoader = MockDataLoader(testName: name)
        let analytics = AnalyticsMock()
        let app = createApplication(dataLoader: dataLoader, analytics: analytics)

        let viewModel = StopViewModel(application: app, stopID: testStopID)

        // First refresh triggers the auto-extend chain (empty results), which itself
        // re-enters refresh() multiple times.
        await viewModel.refresh()

        // Two additional explicit refreshes. With the cap reached, no more auto-extend.
        await viewModel.refresh()
        await viewModel.refresh()

        expect(analytics.stopViewedCount) == 1
        expect(analytics.lastReportedStopID) == testStopID
    }

    // MARK: - Recents recorded once (issue #1)

    /// `addRecentStop` is one-shot per VM lifetime — multiple successful refreshes must not
    /// re-touch the recents list.
    @MainActor
    func test_recentStop_recordedExactlyOnce() async {
        let dataLoader = MockDataLoader(testName: name)
        let analytics = AnalyticsMock()
        let app = createApplication(dataLoader: dataLoader, analytics: analytics)

        let viewModel = StopViewModel(application: app, stopID: testStopID)
        await viewModel.refresh()
        await viewModel.refresh()
        await viewModel.refresh()

        expect(app.userDataStore.recentStops.count) == 1
        expect(app.userDataStore.recentStops.first?.id) == testStopID
    }

    // MARK: - Surveys fetched once

    /// `refreshSurveys()` runs as part of the one-shot initial-fetch block, not on every
    /// auto-refresh — so `surveysDidRefresh` should emit exactly once across multiple
    /// refreshes. The emission happens from a detached `Task`, so assert eventually.
    @MainActor
    func test_surveys_refreshedExactlyOnceAcrossRefreshes() async {
        let dataLoader = MockDataLoader(testName: name)
        let analytics = AnalyticsMock()
        let app = createApplication(dataLoader: dataLoader, analytics: analytics)

        let viewModel = StopViewModel(application: app, stopID: testStopID)

        var emissions = 0
        let cancellable = viewModel.surveysDidRefresh.sink { emissions += 1 }
        defer { cancellable.cancel() }

        await viewModel.refresh()
        await viewModel.refresh()
        await viewModel.refresh()

        await expect(emissions).toEventually(equal(1))
    }

    // MARK: - Filter invariant on initial load (issue #2)

    /// If the persisted preferences for this stop hide every route the stop serves,
    /// the first successful fetch must flip `isListFiltered` to `false` so the user
    /// doesn't land on an empty list.
    @MainActor
    func test_disableFilter_runsOnInitialLoadWhenAllRoutesHidden() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let analytics = AnalyticsMock()
        let app = createApplication(dataLoader: dataLoader, analytics: analytics)

        let region = try XCTUnwrap(app.currentRegion)

        // The fixture's stop serves a single route, "1_R1". Pre-hide it.
        // We need a `Stop` object to call the data-store setter; build a minimal one from JSON.
        let stopJSON = #"{"id":"1_TEST","code":"TEST","name":"Test Stop","lat":47.6,"lon":-122.3,"locationType":0,"routeIds":["1_R1"],"direction":""}"#
        let stub = try JSONDecoder().decode(Stop.self, from: stopJSON.data(using: .utf8)!)
        var prefs = StopPreferences()
        prefs.hiddenRoutes = ["1_R1"]
        app.stopPreferencesDataStore.set(stopPreferences: prefs, stop: stub, region: region)

        let viewModel = StopViewModel(application: app, stopID: testStopID)
        expect(viewModel.isListFiltered).to(beTrue())  // default ON

        await viewModel.refresh()

        expect(viewModel.isListFiltered).to(beFalse())
    }

    // MARK: - $stop re-emit guard

    /// `$stop` must not re-emit across refreshes when the underlying value is unchanged.
    /// Re-emission would re-run the VC's `applyData` + `configureTabBarButtons` + title
    /// assignment for no reason on every 30 s refresh cycle.
    @MainActor
    func test_stop_doesNotReEmitWhenUnchangedAcrossRefreshes() async {
        let dataLoader = MockDataLoader(testName: name)
        let analytics = AnalyticsMock()
        let app = createApplication(dataLoader: dataLoader, analytics: analytics)

        let viewModel = StopViewModel(application: app, stopID: testStopID)

        var emissions = 0
        let cancellable = viewModel.$stop.sink { _ in emissions += 1 }
        defer { cancellable.cancel() }

        await viewModel.refresh()
        let afterFirstRefresh = emissions

        await viewModel.refresh()
        await viewModel.refresh()

        // Baseline: @Published delivers the current value on subscription (nil),
        // plus the first real assignment in refresh() — so afterFirstRefresh is the
        // expected steady state. Subsequent refreshes with the same stop must not
        // increase the count.
        expect(emissions) == afterFirstRefresh
    }

    // MARK: - shouldRefresh threshold

    /// `shouldRefresh` returns `true` when no successful fetch has happened yet, and `false`
    /// immediately after a successful refresh.
    @MainActor
    func test_shouldRefresh_nilLastUpdatedIsTrue_recentLastUpdatedIsFalse() async {
        let dataLoader = MockDataLoader(testName: name)
        let analytics = AnalyticsMock()
        let app = createApplication(dataLoader: dataLoader, analytics: analytics)

        let viewModel = StopViewModel(application: app, stopID: testStopID)
        expect(viewModel.lastUpdated).to(beNil())
        expect(viewModel.shouldRefresh).to(beTrue())

        await viewModel.refresh()

        expect(viewModel.lastUpdated).toNot(beNil())
        expect(viewModel.shouldRefresh).to(beFalse())  // <30 s elapsed → below threshold
    }
}
