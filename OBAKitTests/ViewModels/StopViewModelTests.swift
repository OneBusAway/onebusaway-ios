//
//  StopViewModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import Combine
import CoreLocation
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast force_try

/// Tests for `StopViewModel`. Regression tests for review issues #1, #2, and #8.
@Suite(.serialized)
final class StopViewModelTests: OBATestCase {
    let testStopID = "1_TEST"
    var queue: OperationQueue!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    // MARK: - Application Builder

    /// Builds an `Application` whose REST API service routes through the supplied `MockDataLoader`.
    /// Locks the current region to Puget Sound so the API base URL is deterministic.
    ///
    /// Pass `bundledRegionsFixture: "regions-puget-sound-no-sidecar.json"` for a Puget
    /// Sound with no `sidecarBaseURL`, which leaves `application.obacoService` nil —
    /// the configuration the alarm paths have to survive.
    private func createApplication(
        dataLoader: MockDataLoader,
        analytics: AnalyticsMock,
        surveyHitCounter: SurveyHitCounter? = nil,
        arrivalsFixture: String = "arrivals_and_departures_empty.json",
        arrivalsData: Data? = nil,
        arrivalsFailureStatusCode: Int? = nil,
        bundledRegionsFixture: String? = nil,
        defaultArrivalDepartureFilter: ArrivalDepartureFilter = .all
    ) -> Application {
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        if let arrivalsFailureStatusCode {
            // Empty (non-nil) data: `MockDataLoader.data(for:)` fatal-errors on nil data,
            // and `APIService+GetData` branches on `httpResponse.statusCode` before it
            // ever tries to decode a body.
            dataLoader.mock(data: Data(), statusCode: arrivalsFailureStatusCode) { request in
                request.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false
            }
        } else if let arrivalsData {
            dataLoader.mock(data: arrivalsData) { request in
                request.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false
            }
        } else {
            stubArrivalsAndDepartures(dataLoader: dataLoader, fixture: arrivalsFixture)
        }
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
            bundledRegionsFilePath: bundledRegionsFixture.map { Fixtures.path(to: $0) } ?? bundledRegionsPath,
            regionsAPIPath: regionsAPIPath,
            dataLoader: dataLoader,
            fixedRegionName: Fixtures.pugetSoundRegion.name,
            defaultArrivalDepartureFilter: defaultArrivalDepartureFilter
        )

        return Application(config: config)
    }

    // MARK: - Review Prompt Builders

    /// Builds a `StopViewModel` backed by a real `Application` whose arrivals fetch
    /// returns `arrivalsFixture`. Returns the `Application` alongside the view model
    /// so tests can assert on `application.reviewPromptPolicy`/`promptCoordinator`.
    @MainActor
    private func buildViewModel(arrivalsFixture: String) -> (StopViewModel, Application) {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader, analytics: AnalyticsMock(), arrivalsFixture: arrivalsFixture)
        let viewModel = StopViewModel(application: app, stopID: testStopID)
        return (viewModel, app)
    }

    /// Builds a `StopViewModel` backed by a real `Application` whose arrivals fetch
    /// fails with `statusCode` (no body).
    @MainActor
    private func buildViewModelWithFailingArrivals(statusCode: Int, bookmarkContext: Bookmark? = nil) -> (StopViewModel, Application) {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader, analytics: AnalyticsMock(), arrivalsFailureStatusCode: statusCode)
        let viewModel = StopViewModel(application: app, stopID: testStopID, bookmarkContext: bookmarkContext)
        return (viewModel, app)
    }

    /// Hides every route present in `arrivals_and_departures_for_stop_1_10020.json`
    /// (routes `1_30` and `1_65`) so the rider never sees a real-time row from that
    /// fixture. Writes straight to the view model's in-memory `stopPreferences` via
    /// `updateStopPreferences`, which assigns unconditionally before its `stop`/`region`
    /// persistence guard — so this works even pre-refresh, when `stop` is still nil.
    @MainActor
    private func hideAllRoutes(in viewModel: StopViewModel) {
        var prefs = viewModel.stopPreferences
        prefs.hiddenRoutes = ["1_30", "1_65"]
        viewModel.updateStopPreferences(prefs)
    }

    /// `RegionsService` prefers the on-disk regions file over the bundled one, and a
    /// prior run in the same simulator can leave a copy that *does* have a sidecar URL.
    /// Wipe it so a no-sidecar bundled fixture actually reaches `currentRegion`.
    private func removeStoredRegionsFile() {
        guard let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return }

        try? FileManager.default.removeItem(
            at: appSupport.appendingPathComponent("Regions/default-regions.json")
        )
    }

    /// Stubs every `arrivals-and-departures-for-stop` call with the given fixture.
    /// The matcher is path-based, so the same stub serves every minutesAfter value the VM walks through.
    private func stubArrivalsAndDepartures(dataLoader: MockDataLoader, fixture: String = "arrivals_and_departures_empty.json") {
        let data = Fixtures.loadData(file: fixture)
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
    @Test @MainActor
    func `Auto extend walks to cap and flips exhausted`() async {
        let dataLoader = MockDataLoader(testName: name)
        let analytics = AnalyticsMock()
        let app = createApplication(dataLoader: dataLoader, analytics: analytics)

        let viewModel = StopViewModel(application: app, stopID: testStopID)

        var observed: [UInt] = []
        let cancellable = viewModel.$minutesAfter.sink { observed.append($0) }
        defer { cancellable.cancel() }

        await viewModel.refresh()

        // Strictly increasing trajectory ending at the cap.
        #expect(observed == observed.sorted())
        #expect(observed.last == 720)
        #expect(viewModel.minutesAfter == 720)
        #expect(viewModel.isLoadMoreExhausted)

        // Verify each hop made strict forward progress (no duplicates after the initial value).
        let distinctAscending = Array(NSOrderedSet(array: observed)) as! [UInt]
        #expect(distinctAscending.count == observed.count)
    }

    // MARK: - Analytics fires once (issue #1)

    /// `reportStopViewed` must fire exactly once per VM lifetime, even when refresh() is
    /// invoked many times by the auto-extend chain or by the user.
    @Test @MainActor
    func `Analytics fires exactly once across refreshes`() async {
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

        #expect(analytics.stopViewedCount == 1)
        #expect(analytics.lastReportedStopID == testStopID)
    }

    // MARK: - Recents recorded once (issue #1)

    /// `addRecentStop` is one-shot per VM lifetime — multiple successful refreshes must not
    /// re-touch the recents list.
    @Test @MainActor
    func `Recent stop recorded exactly once`() async {
        let dataLoader = MockDataLoader(testName: name)
        let analytics = AnalyticsMock()
        let app = createApplication(dataLoader: dataLoader, analytics: analytics)

        let viewModel = StopViewModel(application: app, stopID: testStopID)
        await viewModel.refresh()
        await viewModel.refresh()
        await viewModel.refresh()

        #expect(app.userDataStore.recentStops.count == 1)
        #expect(app.userDataStore.recentStops.first?.id == testStopID)
    }

    // MARK: - Surveys fetched once

    /// `refreshSurveys()` runs as part of the one-shot initial-fetch block, not on every
    /// auto-refresh — so the `/surveys.json` endpoint must be hit exactly once across
    /// multiple refreshes. The fetch runs in `surveyRefreshTask`; awaiting it gives an
    /// exact count rather than a polled one.
    @Test @MainActor
    func `Surveys refreshed exactly once across refreshes`() async {
        let dataLoader = MockDataLoader(testName: name)
        let analytics = AnalyticsMock()
        let counter = SurveyHitCounter()
        let app = createApplication(dataLoader: dataLoader, analytics: analytics, surveyHitCounter: counter)

        let viewModel = StopViewModel(application: app, stopID: testStopID)

        await viewModel.refresh()
        await viewModel.refresh()
        await viewModel.refresh()

        // Awaiting the fetch is what makes `== 1` exact: it rules out both "never
        // fetched" and "fetched per refresh" in a single assertion. Polling could
        // only catch the former, and would latch onto a transient 1 on the way to 3.
        await viewModel.surveyRefreshTask?.value
        #expect(counter.hits == 1)
    }

    // MARK: - Filter invariant on initial load (issue #2)

    /// If the persisted preferences for this stop hide every route the stop serves,
    /// the first successful fetch must flip `isListFiltered` to `false` so the user
    /// doesn't land on an empty list.
    @Test @MainActor
    func `Disable filter runs on initial load when all routes hidden`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let analytics = AnalyticsMock()
        let app = createApplication(dataLoader: dataLoader, analytics: analytics)

        let region = try #require(app.currentRegion)

        // The fixture's stop serves a single route, "1_R1". Pre-hide it.
        // We need a `Stop` object to call the data-store setter; build a minimal one from JSON.
        let stopJSON = #"{"id":"1_TEST","code":"TEST","name":"Test Stop","lat":47.6,"lon":-122.3,"locationType":0,"routeIds":["1_R1"],"direction":""}"#
        let stub = try JSONDecoder().decode(Stop.self, from: stopJSON.data(using: .utf8)!)
        var prefs = StopPreferences()
        prefs.hiddenRoutes = ["1_R1"]
        app.stopPreferencesDataStore.set(stopPreferences: prefs, stop: stub, region: region)

        let viewModel = StopViewModel(application: app, stopID: testStopID)
        #expect(viewModel.isListFiltered)  // default ON

        await viewModel.refresh()

        #expect(!viewModel.isListFiltered)
    }

    // MARK: - Departure Type filter

    /// The view model must seed its published filter from the effective value —
    /// which honors the white-label default — since the SwiftUI stop page reads
    /// only the view model, never `UserDefaults`.
    @Test @MainActor
    func `Arrival departure filter seeds from the configured default`() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(
            dataLoader: dataLoader,
            analytics: AnalyticsMock(),
            defaultArrivalDepartureFilter: .scheduledOnly
        )

        let viewModel = StopViewModel(application: app, stopID: testStopID)

        #expect(viewModel.arrivalDepartureFilter == .scheduledOnly)
    }

    /// Updating through the view model persists app-wide, so the legacy page,
    /// the SwiftUI page, and Settings all observe the change.
    @Test @MainActor
    func `Updating the arrival departure filter persists it`() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader, analytics: AnalyticsMock())

        let viewModel = StopViewModel(application: app, stopID: testStopID)
        #expect(viewModel.arrivalDepartureFilter == .all)

        viewModel.updateArrivalDepartureFilter(.estimatedOnly)

        #expect(viewModel.arrivalDepartureFilter == .estimatedOnly)
        #expect(app.effectiveArrivalDepartureFilter == .estimatedOnly)
    }

    // MARK: - $stop re-emit guard

    /// `$stop` must not re-emit across refreshes when the underlying value is unchanged.
    /// Re-emission would re-run the VC's `applyData` + `configureTabBarButtons` + title
    /// assignment for no reason on every 30 s refresh cycle.
    @Test @MainActor
    func `Stop does not re emit when unchanged across refreshes`() async {
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
        #expect(emissions == afterFirstRefresh)
    }

    // MARK: - shouldRefresh threshold

    /// `shouldRefresh` returns `true` when no successful fetch has happened yet, and `false`
    /// immediately after a successful refresh.
    @Test @MainActor
    func `Should refresh nil last updated is true recent last updated is false`() async {
        let dataLoader = MockDataLoader(testName: name)
        let analytics = AnalyticsMock()
        let app = createApplication(dataLoader: dataLoader, analytics: analytics)

        let viewModel = StopViewModel(application: app, stopID: testStopID)
        #expect(viewModel.lastUpdated == nil)
        #expect(viewModel.shouldRefresh)

        await viewModel.refresh()

        #expect(viewModel.lastUpdated != nil)
        #expect(!viewModel.shouldRefresh)  // <30 s elapsed → below threshold
    }

    // MARK: - Inline Hero Survey

    /// On a fresh VM (before any fetch), `currentSurvey` is `nil`.
    @Test @MainActor
    func `Current survey is nil before fetch`() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader, analytics: AnalyticsMock())

        let viewModel = StopViewModel(application: app, stopID: testStopID)

        #expect(viewModel.currentSurvey == nil)
    }

    /// `submitHeroAnswer` with no current survey is a no-op (no error emission, no
    /// presentFullSurvey emission).
    @Test @MainActor
    func `Submit hero answer is no op when no current survey`() async {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader, analytics: AnalyticsMock())

        let viewModel = StopViewModel(application: app, stopID: testStopID)
        var errors: [Error] = []
        var presented: [StopViewModel.FullSurveyPresentation] = []
        let errSub = viewModel.surveySubmissionError.sink { errors.append($0) }
        let presSub = viewModel.presentFullSurvey.sink { presented.append($0) }
        defer { errSub.cancel(); presSub.cancel() }

        await viewModel.submitHeroAnswer("yes", stopLocation: nil)

        #expect(errors.isEmpty)
        #expect(presented.isEmpty)
    }

    /// `dismissCurrentSurvey()` with no current survey is a no-op and does not set
    /// the reminder date.
    @Test @MainActor
    func `Dismiss current survey is no op when no current survey`() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader, analytics: AnalyticsMock())

        let viewModel = StopViewModel(application: app, stopID: testStopID)
        #expect(app.userDataStore.nextSurveyReminderDate == nil)

        viewModel.dismissCurrentSurvey()

        #expect(app.userDataStore.nextSurveyReminderDate == nil)
    }

    /// `launchExternalSurvey()` with no explicit target and no `currentSurvey`
    /// must be a no-op: neither callback fires, and no survey is touched.
    @Test @MainActor
    func `Launch external survey no current survey and no target is no op`() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader, analytics: AnalyticsMock())

        let viewModel = StopViewModel(application: app, stopID: testStopID)
        #expect(viewModel.currentSurvey == nil)

        var successCount = 0
        var failureCount = 0
        viewModel.launchExternalSurvey(
            onSuccess: { successCount += 1 },
            onFailure: { failureCount += 1 }
        )

        #expect(successCount == 0)
        #expect(failureCount == 0)
    }

    /// When an explicit target is passed but the URL cannot be built, the
    /// launcher's failure path runs: `onFailure` fires, `onSuccess` does not,
    /// and the survey stays uncompleted.
    @Test @MainActor
    func `Launch external survey explicit target with no URL calls failure`() {
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

        #expect(failureCount == 1)
        #expect(successCount == 0)
        #expect(!app.userDataStore.isSurveyCompleted(surveyId: survey.id, userIdentifier: app.userDataStore.surveyUserIdentifier))
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
    @Test @MainActor
    func `Current survey populated after refresh when eligible`() async {
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

        #expect(viewModel.currentSurvey?.id == 7)
    }

    /// A review prompt already shown this session suppresses the inline survey
    /// card too, even though `surveyOrchestrator.isEligible()` alone would
    /// still say yes — the coordinator's session-scoped `canShowInlineCards()`
    /// gate must apply to both inline surfaces, not just donations.
    @Test @MainActor
    func `Current survey suppressed after review prompt shown this session`() async {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplicationWithHeroSurvey(
            dataLoader: dataLoader,
            analytics: AnalyticsMock(),
            includeRemainingQuestion: false
        )
        app.userDataStore.alwaysShowSurveysOnStops = true
        app.promptCoordinator.noteShown(.review)

        let viewModel = StopViewModel(application: app, stopID: testStopID)

        await app.surveyService.fetchSurveys()
        await viewModel.refresh()

        #expect(viewModel.currentSurvey == nil)
    }

    /// Hero-only success: submit clears `currentSurvey`, marks the survey
    /// completed, and emits no error / no presentFullSurvey.
    @Test @MainActor
    func `Submit hero answer completed outcome clears card`() async {
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
        #expect(viewModel.currentSurvey != nil)

        var errors: [Error] = []
        var presented: [StopViewModel.FullSurveyPresentation] = []
        let errSub = viewModel.surveySubmissionError.sink { errors.append($0) }
        let presSub = viewModel.presentFullSurvey.sink { presented.append($0) }
        defer { errSub.cancel(); presSub.cancel() }

        let coord = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)
        await viewModel.submitHeroAnswer("yes", stopLocation: coord)

        #expect(viewModel.currentSurvey == nil)
        #expect(errors.isEmpty)
        #expect(presented.isEmpty)
        let userID = app.userDataStore.surveyUserIdentifier
        #expect(app.userDataStore.isSurveyCompleted(surveyId: 7, userIdentifier: userID))
    }

    /// Needs-remaining outcome: card clears AND `presentFullSurvey` emits with the
    /// hero response id (from the canned fixture) and stop location forwarded.
    @Test @MainActor
    func `Submit hero answer needs remaining outcome clears card and emits present`() async {
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
        #expect(viewModel.currentSurvey != nil)

        var errors: [Error] = []
        var presented: [StopViewModel.FullSurveyPresentation] = []
        let errSub = viewModel.surveySubmissionError.sink { errors.append($0) }
        let presSub = viewModel.presentFullSurvey.sink { presented.append($0) }
        defer { errSub.cancel(); presSub.cancel() }

        let coord = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)
        await viewModel.submitHeroAnswer("yes", stopLocation: coord)

        #expect(viewModel.currentSurvey == nil)
        #expect(errors.isEmpty)
        #expect(presented.count == 1)
        #expect(presented.first?.survey.id == 7)
        #expect(presented.first?.heroResponseID == "808d3a515daa39f4c15a")
        #expect(presented.first?.stopLocation?.latitude == coord.latitude)
        #expect(presented.first?.stopLocation?.longitude == coord.longitude)
        // Hero-only success path runs mark-completed; needs-remaining does not.
        let userID = app.userDataStore.surveyUserIdentifier
        #expect(!app.userDataStore.isSurveyCompleted(surveyId: 7, userIdentifier: userID))
    }

    /// Submission failure path: `currentSurvey` is preserved and the error
    /// publisher emits exactly once.
    @Test @MainActor
    func `Submit hero answer error path emits error and keeps card`() async {
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
        #expect(viewModel.currentSurvey != nil)

        var errors: [Error] = []
        let errSub = viewModel.surveySubmissionError.sink { errors.append($0) }
        defer { errSub.cancel() }

        await viewModel.submitHeroAnswer("yes", stopLocation: nil)

        #expect(errors.count == 1)
        #expect(viewModel.currentSurvey != nil)
    }

    /// Re-entrancy guard: a second concurrent `submitHeroAnswer` is dropped while
    /// the first is in flight, so the survey is only marked completed once and
    /// `presentFullSurvey` does not double-fire on the needs-remaining path.
    @Test @MainActor
    func `Submit hero answer re entrancy guard blocks concurrent submit`() async {
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
        #expect(viewModel.currentSurvey != nil)

        var presented: [StopViewModel.FullSurveyPresentation] = []
        let presSub = viewModel.presentFullSurvey.sink { presented.append($0) }
        defer { presSub.cancel() }

        // Kick off two concurrent submits.
        async let a: Void = viewModel.submitHeroAnswer("yes", stopLocation: nil)
        async let b: Void = viewModel.submitHeroAnswer("yes", stopLocation: nil)
        _ = await (a, b)

        // First submit clears `currentSurvey`; second submit's guard (nil currentSurvey
        // OR heroSubmitInFlight) prevents a duplicate emission.
        #expect(presented.count == 1)
    }

    // MARK: - Router transfer fallback (final-review FIX 1)

    /// A transfer (non-nil `TransferContext`) must always resolve to the legacy
    /// `StopViewController`, even with the new-stop-page flag ON (its default),
    /// because the transfer UX isn't built on the new page yet. A plain open with
    /// the flag ON resolves to the new `StopPageViewController`.
    @Test @MainActor
    func `Make stop controller transfer context falls back to legacy screen`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader, analytics: AnalyticsMock())

        // The new-stop-page flag defaults to ON when unset.
        #expect(FeatureFlags.isNewStopPageEnabled(userDefaults: app.userDefaults))

        let stop = try #require(try Fixtures.loadSomeStops().first)

        let transfer = TransferContext(arrivalTime: Date(), fromRouteShortName: "1", fromTripHeadsign: "Downtown")
        let transferController = app.viewRouter.makeStopController(stop: stop, transferContext: transfer)
        #expect(transferController is StopViewController)

        let plainController = app.viewRouter.makeStopController(stop: stop, transferContext: nil)
        #expect(plainController is StopPageViewController)
    }

    // MARK: - Alarm Lead Time

    /// `alarmLeadTimeMinutes` derives the displayed lead time from the alarm's
    /// `tripDate`/`alarmDate` spread, not from any stored minutes field.
    @Test @MainActor
    func `Alarm lead time minutes derives from dates`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader, analytics: AnalyticsMock())
        let viewModel = StopViewModel(application: app, stopID: testStopID)

        let alarm = try Fixtures.loadAlarm()
        alarm.set(tripDate: Date(timeIntervalSinceNow: 600), alarmOffset: 8)

        #expect(viewModel.alarmLeadTimeMinutes(alarm) == 8)
    }

    /// With no `tripDate`/`alarmDate` to measure, the lead time falls back to the
    /// default rather than surfacing a bogus value.
    @Test @MainActor
    func `Alarm lead time minutes falls back to default on nil dates`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader, analytics: AnalyticsMock())
        let viewModel = StopViewModel(application: app, stopID: testStopID)

        // A freshly decoded alarm has nil `tripDate`/`alarmDate` until `set(...)`.
        let alarm = try Fixtures.loadAlarm()
        #expect(alarm.tripDate == nil)
        #expect(alarm.alarmDate == nil)

        #expect(viewModel.alarmLeadTimeMinutes(alarm) == AlarmLeadTime.defaultMinutes)
    }

    // MARK: - Alarm Cancellation

    /// Cancelling with no Obaco service must not report success: the server alarm is
    /// still armed and will still fire, so dropping the local copy would leave the
    /// rider with a buzzing alarm they can no longer see or cancel.
    @Test @MainActor
    func `Cancel alarm without obaco service keeps alarm and surfaces error`() async throws {
        removeStoredRegionsFile()

        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(
            dataLoader: dataLoader,
            analytics: AnalyticsMock(),
            arrivalsFixture: "arrivals_and_departures_for_stop_1_10020.json",
            bundledRegionsFixture: "regions-puget-sound-no-sidecar.json"
        )

        // Precondition: no sidecar URL means no Obaco service to delete against.
        #expect(app.obacoService == nil)

        let viewModel = StopViewModel(application: app, stopID: testStopID)
        await viewModel.refresh()

        let departure = try #require(viewModel.stopArrivals?.arrivalsAndDepartures.first)
        let region = try #require(app.currentRegion)

        let alarm = try Fixtures.loadAlarm()
        alarm.deepLink = ArrivalDepartureDeepLink(arrivalDeparture: departure, regionID: region.regionIdentifier)
        // A trip in the future, so `deleteExpiredAlarms()` doesn't prune it out from under us.
        alarm.set(tripDate: Date(timeIntervalSinceNow: 900), alarmOffset: 5)
        app.userDataStore.add(alarm: alarm)

        // The index is rebuilt from the persisted store on each successful fetch.
        await viewModel.refresh()
        #expect(viewModel.alarm(for: departure) != nil)

        await viewModel.cancelAlarm(for: departure)

        #expect(viewModel.alarmError != nil)
        #expect(viewModel.alarm(for: departure) != nil)
        #expect(!app.userDataStore.alarms.isEmpty)
    }

    // MARK: - Review prompt success recording

    @Test @MainActor
    func `Successful fetch with predicted arrival records one success`() async {
        let (viewModel, application) = buildViewModel(arrivalsFixture: "arrivals_and_departures_for_stop_1_10020.json")
        await viewModel.refresh()
        #expect(application.reviewPromptPolicy.successCount == 1)
    }

    @Test @MainActor
    func `Repeated refreshes record only one success`() async {
        let (viewModel, application) = buildViewModel(arrivalsFixture: "arrivals_and_departures_for_stop_1_10020.json")
        await viewModel.refresh()
        await viewModel.refresh()
        await viewModel.refresh()
        #expect(application.reviewPromptPolicy.successCount == 1)
    }

    @Test @MainActor
    func `Scheduled only arrivals record no success`() async {
        let (viewModel, application) = buildViewModel(arrivalsFixture: "arrivals_and_departures_for_stop_1_10020_no_realtime.json")
        await viewModel.refresh()
        #expect(application.reviewPromptPolicy.successCount == 0)
    }

    /// Hide every route the fixture's predicted arrivals belong to, so the rider
    /// never saw a real-time row.
    @Test @MainActor
    func `Predicted arrival on hidden route records no success`() async {
        let (viewModel, application) = buildViewModel(arrivalsFixture: "arrivals_and_departures_for_stop_1_10020.json")
        hideAllRoutes(in: viewModel)
        await viewModel.refresh()
        #expect(application.reviewPromptPolicy.successCount == 0)
    }

    @Test @MainActor
    func `Failed fetch records no success and flags error`() async {
        let (viewModel, application) = buildViewModelWithFailingArrivals(statusCode: 500)
        await viewModel.refresh()
        #expect(application.reviewPromptPolicy.successCount == 0)
        #expect(application.promptCoordinator.sawErrorThisSession)
    }

    /// A broken bookmark is not a failure the rider watched happen: the page says so
    /// and offers a way out.
    @Test @MainActor
    func `Request not found with bookmark context does not flag error`() async throws {
        let stop = try #require(try Fixtures.loadSomeStops().first)
        let bookmark = Bookmark(name: "Broken", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        let (viewModel, application) = buildViewModelWithFailingArrivals(statusCode: 404, bookmarkContext: bookmark)
        await viewModel.refresh()
        #expect(!application.promptCoordinator.sawErrorThisSession)
    }

    /// Without a bookmark behind it — a deep link, a search result, a map pin — the same
    /// 404 strands the rider on a page with no arrivals and no error, which counts.
    @Test @MainActor
    func `Request not found without bookmark context flags error`() async {
        let (viewModel, application) = buildViewModelWithFailingArrivals(statusCode: 404)
        await viewModel.refresh()
        #expect(application.promptCoordinator.sawErrorThisSession)
    }
}
