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
import CoreLocation
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
    private func createApplication(
        dataLoader: MockDataLoader,
        analytics: AnalyticsMock,
        surveyHitCounter: SurveyHitCounter? = nil
    ) -> Application {
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        stubArrivalsAndDepartures(dataLoader: dataLoader)
        if let surveyHitCounter {
            stubSurveys(dataLoader: dataLoader, counter: surveyHitCounter)
        } else {
            stubSurveys(dataLoader: dataLoader)
        }

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

    /// Stubs the surveys endpoint with an empty-list payload so `refreshSurveys()` succeeds
    /// (routing nothing to `lastError`) instead of leaving the request unmocked.
    private func stubSurveys(dataLoader: MockDataLoader) {
        let emptySurveys = #"{"surveys":[],"region":{"id":1,"name":"Puget Sound"}}"#.data(using: .utf8)!
        dataLoader.mock(data: emptySurveys) { request in
            request.url?.path.contains("/surveys.json") ?? false
        }
    }

    /// Counter for `/surveys.json` requests. `MockDataLoader` matchers are evaluated on the
    /// data-loader's serial queue, so a non-isolated `var` is safe.
    private final class SurveyHitCounter: @unchecked Sendable {
        nonisolated(unsafe) var hits = 0
    }

    /// Same as `stubSurveys` but increments `counter.hits` on each matched request, so a
    /// test can assert how many times `refreshSurveys()` reached the wire.
    private func stubSurveys(dataLoader: MockDataLoader, counter: SurveyHitCounter) {
        let emptySurveys = #"{"surveys":[],"region":{"id":1,"name":"Puget Sound"}}"#.data(using: .utf8)!
        dataLoader.mock(data: emptySurveys) { request in
            guard request.url?.path.contains("/surveys.json") ?? false else { return false }
            counter.hits += 1
            return true
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
    /// auto-refresh — so the `/surveys.json` endpoint must be hit exactly once across
    /// multiple refreshes. The fetch happens from a detached `Task`, so assert eventually.
    @MainActor
    func test_surveys_refreshedExactlyOnceAcrossRefreshes() async {
        let dataLoader = MockDataLoader(testName: name)
        let analytics = AnalyticsMock()
        let counter = SurveyHitCounter()
        let app = createApplication(dataLoader: dataLoader, analytics: analytics, surveyHitCounter: counter)

        let viewModel = StopViewModel(application: app, stopID: testStopID)

        await viewModel.refresh()
        await viewModel.refresh()
        await viewModel.refresh()

        await expect(counter.hits).toEventually(equal(1))
        // Guard against regression to per-refresh fetching: hits must not climb past 1.
        // Without this, `toEventually` would latch onto the transient `1` on its way to 2/3.
        await expect(counter.hits).toNever(beGreaterThan(1))
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

    // MARK: - Inline Hero Survey

    /// On a fresh VM (before any fetch), `currentSurvey` is `nil`.
    @MainActor
    func test_currentSurvey_isNilBeforeFetch() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader, analytics: AnalyticsMock())

        let viewModel = StopViewModel(application: app, stopID: testStopID)

        expect(viewModel.currentSurvey).to(beNil())
    }

    /// `submitHeroAnswer` with no current survey is a no-op (no error emission, no
    /// presentFullSurvey emission).
    @MainActor
    func test_submitHeroAnswer_isNoOpWhenNoCurrentSurvey() async {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader, analytics: AnalyticsMock())

        let viewModel = StopViewModel(application: app, stopID: testStopID)
        var errors: [Error] = []
        var presented: [StopViewModel.FullSurveyPresentation] = []
        let errSub = viewModel.surveySubmissionError.sink { errors.append($0) }
        let presSub = viewModel.presentFullSurvey.sink { presented.append($0) }
        defer { errSub.cancel(); presSub.cancel() }

        await viewModel.submitHeroAnswer("yes", stopLocation: nil)

        expect(errors).to(beEmpty())
        expect(presented).to(beEmpty())
    }

    /// `dismissCurrentSurvey()` with no current survey is a no-op and does not set
    /// the reminder date.
    @MainActor
    func test_dismissCurrentSurvey_isNoOpWhenNoCurrentSurvey() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader, analytics: AnalyticsMock())

        let viewModel = StopViewModel(application: app, stopID: testStopID)
        expect(app.userDataStore.nextSurveyReminderDate).to(beNil())

        viewModel.dismissCurrentSurvey()

        expect(app.userDataStore.nextSurveyReminderDate).to(beNil())
    }

    /// `launchExternalSurvey()` with no explicit target and no `currentSurvey`
    /// must be a no-op: neither callback fires, and no survey is touched.
    @MainActor
    func test_launchExternalSurvey_noCurrentSurveyAndNoTarget_isNoOp() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader, analytics: AnalyticsMock())

        let viewModel = StopViewModel(application: app, stopID: testStopID)
        expect(viewModel.currentSurvey).to(beNil())

        var successCount = 0
        var failureCount = 0
        viewModel.launchExternalSurvey(
            onSuccess: { successCount += 1 },
            onFailure: { failureCount += 1 }
        )

        expect(successCount) == 0
        expect(failureCount) == 0
    }

    /// When an explicit target is passed but the URL cannot be built, the
    /// launcher's failure path runs: `onFailure` fires, `onSuccess` does not,
    /// and the survey stays uncompleted.
    @MainActor
    func test_launchExternalSurvey_explicitTargetWithNoURL_callsFailure() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader, analytics: AnalyticsMock())
        let viewModel = StopViewModel(application: app, stopID: testStopID)

        // External-survey question with no `url:` → builder returns nil → launcher fails.
        let external = SurveyQuestion(
            id: 1,
            position: 1,
            required: true,
            content: QuestionContent(labelText: "q1", type: .externalSurvey)
        )
        let survey = Survey(
            id: 99,
            name: "External",
            createdAt: Date(),
            updatedAt: Date(),
            showOnMap: false,
            showOnStops: true,
            startDate: nil,
            endDate: nil,
            visibleStopsList: nil,
            visibleRoutesList: nil,
            allowsMultipleResponses: false,
            alwaysVisible: false,
            study: Study(id: 1, name: "Study", description: "desc"),
            questions: [external]
        )

        var successCount = 0
        var failureCount = 0
        viewModel.launchExternalSurvey(
            survey,
            onSuccess: { successCount += 1 },
            onFailure: { failureCount += 1 }
        )

        expect(failureCount) == 1
        expect(successCount) == 0
        expect(app.userDataStore.isSurveyCompleted(surveyId: survey.id, userIdentifier: app.userDataStore.surveyUserIdentifier)).to(beFalse())
    }

    // MARK: - Inline Hero Success Paths

    /// Builds an application with a non-empty surveys.json stub. The stubbed survey
    /// is always-visible, hero question at position 1, optional follow-ups, and matches
    /// any stop/route (no `visibleStopsList`/`visibleRoutesList`).
    private func createApplicationWithHeroSurvey(
        dataLoader: MockDataLoader,
        analytics: AnalyticsMock,
        includeRemainingQuestion: Bool,
        stubSubmitResponse: Bool = true
    ) -> Application {
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        stubArrivalsAndDepartures(dataLoader: dataLoader)
        stubHeroSurvey(dataLoader: dataLoader, includeRemainingQuestion: includeRemainingQuestion)
        if stubSubmitResponse {
            stubSurveySubmitResponse(dataLoader: dataLoader)
        }

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

    private func stubHeroSurvey(dataLoader: MockDataLoader, includeRemainingQuestion: Bool) {
        let hero = SurveyQuestion(
            id: 1, position: 1, required: true,
            content: QuestionContent(labelText: "Hero?", type: .text)
        )
        var questions = [hero]
        if includeRemainingQuestion {
            questions.append(SurveyQuestion(
                id: 2, position: 2, required: false,
                content: QuestionContent(labelText: "Follow?", type: .text)
            ))
        }
        let survey = Survey(
            id: 7, name: "Inline Hero",
            createdAt: Date(), updatedAt: Date(),
            showOnMap: false, showOnStops: true,
            startDate: nil, endDate: nil,
            visibleStopsList: nil, visibleRoutesList: nil,
            allowsMultipleResponses: false, alwaysVisible: true,
            study: Study(id: 1, name: "Study", description: "desc"),
            questions: questions
        )
        let studyResponse = StudyResponse(
            surveys: [survey],
            region: SurveyRegion(id: 1, name: "Test")
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode(studyResponse)
        dataLoader.mock(data: data) { request in
            request.url?.path.contains("/surveys.json") ?? false
        }
    }

    private func stubSurveySubmitResponse(dataLoader: MockDataLoader) {
        let data = try! Data(contentsOf: Bundle(for: StopViewModelTests.self)
            .url(forResource: "survey_submission_response", withExtension: "json")!)
        dataLoader.mock(data: data) { request in
            request.url?.path.contains("/api/v1/survey_responses") ?? false
        }
    }

    /// After a refresh, `currentSurvey` becomes non-nil when the survey list is
    /// populated, eligibility is open, and a matching survey exists.
    @MainActor
    func test_currentSurvey_populatedAfterRefreshWhenEligible() async {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplicationWithHeroSurvey(
            dataLoader: dataLoader,
            analytics: AnalyticsMock(),
            includeRemainingQuestion: false
        )
        app.userDataStore.alwaysShowSurveysOnStops = true

        let viewModel = StopViewModel(application: app, stopID: testStopID)

        // Prime the survey list directly so the post-refresh recompute resolves
        // a non-nil current survey deterministically (the refreshSurveys Task
        // fires-and-forgets; awaiting it here keeps the test free of timing flakes).
        await app.surveyService.fetchSurveys()
        await viewModel.refresh()

        expect(viewModel.currentSurvey?.id) == 7
    }

    /// Hero-only success: submit clears `currentSurvey`, marks the survey
    /// completed, and emits no error / no presentFullSurvey.
    @MainActor
    func test_submitHeroAnswer_completedOutcome_clearsCard() async {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplicationWithHeroSurvey(
            dataLoader: dataLoader,
            analytics: AnalyticsMock(),
            includeRemainingQuestion: false
        )
        app.userDataStore.alwaysShowSurveysOnStops = true

        let viewModel = StopViewModel(application: app, stopID: testStopID)
        await app.surveyService.fetchSurveys()
        await viewModel.refresh()
        expect(viewModel.currentSurvey).toNot(beNil())

        var errors: [Error] = []
        var presented: [StopViewModel.FullSurveyPresentation] = []
        let errSub = viewModel.surveySubmissionError.sink { errors.append($0) }
        let presSub = viewModel.presentFullSurvey.sink { presented.append($0) }
        defer { errSub.cancel(); presSub.cancel() }

        let coord = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)
        await viewModel.submitHeroAnswer("yes", stopLocation: coord)

        expect(viewModel.currentSurvey).to(beNil())
        expect(errors).to(beEmpty())
        expect(presented).to(beEmpty())
        let userID = app.userDataStore.surveyUserIdentifier
        expect(app.userDataStore.isSurveyCompleted(surveyId: 7, userIdentifier: userID)).to(beTrue())
    }

    /// Needs-remaining outcome: card clears AND `presentFullSurvey` emits with the
    /// hero response id (from the canned fixture) and stop location forwarded.
    @MainActor
    func test_submitHeroAnswer_needsRemainingOutcome_clearsCardAndEmitsPresent() async {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplicationWithHeroSurvey(
            dataLoader: dataLoader,
            analytics: AnalyticsMock(),
            includeRemainingQuestion: true
        )
        app.userDataStore.alwaysShowSurveysOnStops = true

        let viewModel = StopViewModel(application: app, stopID: testStopID)
        await app.surveyService.fetchSurveys()
        await viewModel.refresh()
        expect(viewModel.currentSurvey).toNot(beNil())

        var errors: [Error] = []
        var presented: [StopViewModel.FullSurveyPresentation] = []
        let errSub = viewModel.surveySubmissionError.sink { errors.append($0) }
        let presSub = viewModel.presentFullSurvey.sink { presented.append($0) }
        defer { errSub.cancel(); presSub.cancel() }

        let coord = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)
        await viewModel.submitHeroAnswer("yes", stopLocation: coord)

        expect(viewModel.currentSurvey).to(beNil())
        expect(errors).to(beEmpty())
        expect(presented.count) == 1
        expect(presented.first?.survey.id) == 7
        expect(presented.first?.heroResponseID) == "808d3a515daa39f4c15a"
        expect(presented.first?.stopLocation?.latitude) == coord.latitude
        expect(presented.first?.stopLocation?.longitude) == coord.longitude
        // Hero-only success path runs mark-completed; needs-remaining does not.
        let userID = app.userDataStore.surveyUserIdentifier
        expect(app.userDataStore.isSurveyCompleted(surveyId: 7, userIdentifier: userID)).to(beFalse())
    }

    /// Submission failure path: `currentSurvey` is preserved and the error
    /// publisher emits exactly once.
    @MainActor
    func test_submitHeroAnswer_errorPath_emitsErrorAndKeepsCard() async {
        let dataLoader = MockDataLoader(testName: name)
        // Stub the surveys list, but NOT the submit endpoint — submission throws.
        let app = createApplicationWithHeroSurvey(
            dataLoader: dataLoader,
            analytics: AnalyticsMock(),
            includeRemainingQuestion: false,
            stubSubmitResponse: false
        )
        app.userDataStore.alwaysShowSurveysOnStops = true
        // Make the submit endpoint *fail* explicitly: stub it to a 500 by returning
        // an error response. MockDataLoader fatal-errors on a totally unmocked URL,
        // so we have to mock it with an error.
        // Match POST specifically so this can't silently swallow a future
        // PUT-based stub registered in the same test setup.
        let errorResponse = MockDataResponse(
            data: nil,
            urlResponse: HTTPURLResponse(url: URL(string: "https://onebusaway.co/api/v1/survey_responses/")!, statusCode: 500, httpVersion: "2", headerFields: nil)!,
            error: URLError(.badServerResponse)
        ) { req in
            req.httpMethod == "POST" && (req.url?.path.contains("/api/v1/survey_responses") ?? false)
        }
        dataLoader.mock(response: errorResponse)

        let viewModel = StopViewModel(application: app, stopID: testStopID)
        await app.surveyService.fetchSurveys()
        await viewModel.refresh()
        expect(viewModel.currentSurvey).toNot(beNil())

        var errors: [Error] = []
        let errSub = viewModel.surveySubmissionError.sink { errors.append($0) }
        defer { errSub.cancel() }

        await viewModel.submitHeroAnswer("yes", stopLocation: nil)

        expect(errors.count) == 1
        expect(viewModel.currentSurvey).toNot(beNil())
    }

    /// Re-entrancy guard: a second concurrent `submitHeroAnswer` is dropped while
    /// the first is in flight, so the survey is only marked completed once and
    /// `presentFullSurvey` does not double-fire on the needs-remaining path.
    @MainActor
    func test_submitHeroAnswer_reEntrancyGuard_blocksConcurrentSubmit() async {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplicationWithHeroSurvey(
            dataLoader: dataLoader,
            analytics: AnalyticsMock(),
            includeRemainingQuestion: true
        )
        app.userDataStore.alwaysShowSurveysOnStops = true

        let viewModel = StopViewModel(application: app, stopID: testStopID)
        await app.surveyService.fetchSurveys()
        await viewModel.refresh()
        expect(viewModel.currentSurvey).toNot(beNil())

        var presented: [StopViewModel.FullSurveyPresentation] = []
        let presSub = viewModel.presentFullSurvey.sink { presented.append($0) }
        defer { presSub.cancel() }

        // Kick off two concurrent submits.
        async let a: Void = viewModel.submitHeroAnswer("yes", stopLocation: nil)
        async let b: Void = viewModel.submitHeroAnswer("yes", stopLocation: nil)
        _ = await (a, b)

        // First submit clears `currentSurvey`; second submit's guard (nil currentSurvey
        // OR heroSubmitInFlight) prevents a duplicate emission.
        expect(presented.count) == 1
    }
}
