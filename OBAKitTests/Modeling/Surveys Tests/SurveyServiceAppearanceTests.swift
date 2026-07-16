//
//  SurveyServiceAppearanceTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
@testable import OBAKitCore

final class SurveyServiceAppearanceTests: OBATestCase {

    nonisolated(unsafe) private var testUserDefaults: UserDefaults!
    nonisolated(unsafe) private var store: UserDefaultsStore!

    override func setUp() async throws {
        try await super.setUp()
        testUserDefaults = buildUserDefaults(suiteName: "\(userDefaultsSuiteName).appearance")
        testUserDefaults.removePersistentDomain(forName: "\(userDefaultsSuiteName).appearance")
        store = UserDefaultsStore(userDefaults: testUserDefaults)
    }

    override func tearDown() async throws {
        testUserDefaults.removePersistentDomain(forName: "\(userDefaultsSuiteName).appearance")
        try await super.tearDown()
    }

    // MARK: - visibleSurveys filtering (date activity) ----------------------

    func test_fetch_mixedActiveAndExpired_visibleSurveysExcludesExpired() async {
        let service = await fetchService([
            makeSurvey(id: 1),                                   // active
            makeSurvey(id: 2, startDate: hoursAgo(2), endDate: hoursAgo(1)), // expired
            makeSurvey(id: 3, startDate: hoursFromNow(1), endDate: hoursFromNow(2)) // future
        ])

        expect(service.allSurveys.count).to(equal(3))
        expect(service.visibleSurveys.map(\.id)).to(equal([1]))
    }

    func test_fetch_allInactive_visibleEmpty_andFindReturnsNil() async {
        let service = await fetchService([
            makeSurvey(id: 1, showOnStops: true, startDate: hoursAgo(2), endDate: hoursAgo(1)),
            makeSurvey(id: 2, showOnStops: true, startDate: hoursFromNow(1), endDate: hoursFromNow(2))
        ])

        expect(service.allSurveys.count).to(equal(2))
        expect(service.visibleSurveys).to(beEmpty())
        expect(service.findSurveyForMap()).to(beNil())
        expect(service.findSurveyForStop(stopID: "STOP_A", routeIDs: ["R1"])).to(beNil())
    }

    func test_fetch_surveyWithOpenEndedDates_isActive() async {
        // nil start + nil end => always within range.
        let service = await fetchService([makeSurvey(id: 1, startDate: nil, endDate: nil)])
        expect(service.findSurveyForMap()?.id).to(equal(1))
    }

    // MARK: - Stop targeting matrix ----------------------------------------

    func test_findSurveyForStop_nilStopList_nilRouteList_showsAtAnyStop() async {
        let service = await fetchService([
            makeSurvey(id: 1, showOnStops: true, stopList: nil, routesList: nil)
        ])
        expect(service.findSurveyForStop(stopID: "ANY_STOP", routeIDs: []).map(\.id)).to(equal(1))
    }

    func test_findSurveyForStop_stopInList_shows() async {
        let service = await fetchService([
            makeSurvey(id: 1, showOnStops: true, stopList: ["STOP_A", "STOP_B"])
        ])
        expect(service.findSurveyForStop(stopID: "STOP_B", routeIDs: []).map(\.id)).to(equal(1))
    }

    func test_findSurveyForStop_stopNotInList_routeMatches_shows() async {
        let service = await fetchService([
            makeSurvey(id: 1, showOnStops: true, stopList: ["STOP_A"], routesList: ["R9"])
        ])
        // The stop is not listed, but one of its routes is.
        expect(service.findSurveyForStop(stopID: "STOP_Z", routeIDs: ["R9"]).map(\.id)).to(equal(1))
    }

    func test_findSurveyForStop_stopNotInList_routeNotInList_returnsNil() async {
        let service = await fetchService([
            makeSurvey(id: 1, showOnStops: true, stopList: ["STOP_A"], routesList: ["R9"])
        ])
        expect(service.findSurveyForStop(stopID: "STOP_Z", routeIDs: ["R1"])).to(beNil())
    }

    func test_findSurveyForStop_showOnStopsFalse_returnsNil() async {
        let service = await fetchService([
            makeSurvey(id: 1, showOnMap: true, showOnStops: false)
        ])
        expect(service.findSurveyForStop(stopID: "STOP_A", routeIDs: ["R1"])).to(beNil())
    }

    // An empty stop/route list means "no restriction" — identical to nil — so a
    // stops-enabled survey with both lists empty appears on every stop,
    // regardless of the stop's routes.
    func test_findSurveyForStop_emptyStopAndRouteLists_showsAtAnyStop() async {
        let service = await fetchService([
            makeSurvey(id: 1, showOnStops: true, stopList: [], routesList: [])
        ])
        expect(service.findSurveyForStop(stopID: "STOP_A", routeIDs: ["R1"]).map(\.id)).to(equal(1))
        expect(service.findSurveyForStop(stopID: "STOP_OTHER", routeIDs: []).map(\.id)).to(equal(1))
    }

    // A survey scoped to a specific stop list with no route targeting (nil/empty
    // route list) must NOT leak onto stops outside its list. A nil/empty route
    // list means "no route-based targeting" — it contributes nothing — not
    // "every route".
    func test_findSurveyForStop_stopScoped_nilRouteList_doesNotLeakToUnlistedStop() async {
        let service = await fetchService([
            makeSurvey(id: 1, showOnStops: true, stopList: ["STOP_A"], routesList: nil)
        ])
        // Listed stop: shows.
        expect(service.findSurveyForStop(stopID: "STOP_A", routeIDs: ["R1"]).map(\.id)).to(equal(1))
        // Unlisted stop must not match, regardless of the stop's routes.
        expect(service.findSurveyForStop(stopID: "STOP_Z", routeIDs: ["R1"])).to(beNil())
        expect(service.findSurveyForStop(stopID: "STOP_Z", routeIDs: [])).to(beNil())
    }

    func test_findSurveyForStop_routeScoped_nilStopList_showsOnlyOnServedStops() async {
        let service = await fetchService([
            makeSurvey(id: 1, showOnStops: true, stopList: nil, routesList: ["R9"])
        ])
        // Any stop served by R9 shows it...
        expect(service.findSurveyForStop(stopID: "STOP_A", routeIDs: ["R9"]).map(\.id)).to(equal(1))
        expect(service.findSurveyForStop(stopID: "STOP_B", routeIDs: ["R9", "R1"]).map(\.id)).to(equal(1))
        // ...stops not served by R9 do not.
        expect(service.findSurveyForStop(stopID: "STOP_A", routeIDs: ["R1"])).to(beNil())
    }

    // MARK: - Map targeting -------------------------------------------------

    func test_findSurveyForMap_showOnMapFalse_returnsNil() async {
        let service = await fetchService([
            makeSurvey(id: 1, showOnMap: false, showOnStops: true)
        ])
        expect(service.findSurveyForMap()).to(beNil())
    }

    func test_findSurveyForMap_skipsStopOnlySurvey_returnsMapSurvey() async {
        let service = await fetchService([
            makeSurvey(id: 1, showOnMap: false, showOnStops: true),
            makeSurvey(id: 2, showOnMap: true, showOnStops: false)
        ])
        expect(service.findSurveyForMap()?.id).to(equal(2))
    }

    // MARK: - Empty-question gating ----------------------------------------

    func test_findSurvey_skipsSurveyWithNoQuestions_returnsNextValidSurvey() async {
        let service = await fetchService([
            makeSurvey(id: 1, questions: []),                  // no questions -> skipped
            makeSurvey(id: 2, questions: makeQuestions())      // valid
        ])
        expect(service.findSurveyForMap()?.id).to(equal(2))
    }

    func test_findSurvey_onlySurveyHasNoQuestions_returnsNil() async {
        let service = await fetchService([makeSurvey(id: 1, questions: [])])
        expect(service.findSurveyForMap()).to(beNil())
    }

    // MARK: - Priority ordering --------------------------------------------

    // Always-visible single-response surveys are documented as the highest
    // priority and are returned immediately — even when an incomplete one-time
    // survey appears earlier in the list. This pins that ordering contract.
    func test_priority_alwaysVisibleSingle_beatsEarlierOneTime() async {
        let service = await fetchService([
            makeSurvey(id: 1),                          // one-time, incomplete (earlier)
            makeSurvey(id: 2, alwaysVisible: true)      // always-visible single (later)
        ])
        expect(service.findSurveyForMap()?.id).to(equal(2))
    }

    func test_priority_completedAlwaysVisibleSingle_fallsThroughToOneTime() async {
        let userID = store.surveyUserIdentifier
        store.markSurveyCompleted(surveyId: 2, userIdentifier: userID)

        let service = await fetchService([
            makeSurvey(id: 1),                          // one-time, incomplete
            makeSurvey(id: 2, alwaysVisible: true)      // always-visible single, completed
        ])
        // The always-visible single is exhausted, so the one-time wins.
        expect(service.findSurveyForMap()?.id).to(equal(1))
    }

    func test_priority_oneTimeIncomplete_beatsAlwaysVisibleMulti() async {
        let service = await fetchService([
            makeSurvey(id: 1, multipleResponses: true, alwaysVisible: true), // lowest priority
            makeSurvey(id: 2)                                                 // one-time incomplete
        ])
        expect(service.findSurveyForMap()?.id).to(equal(2))
    }

    // MARK: - Completion / dismissal ---------------------------------------

    func test_dismissSurvey_hidesOneTimeSurvey() async {
        let service = await fetchService([makeSurvey(id: 1)])
        expect(service.findSurveyForMap()?.id).to(equal(1))

        service.dismissSurvey(service.allSurveys[0])
        expect(service.findSurveyForMap()).to(beNil())
    }

    func test_markCompleted_hidesOneTime_butMultiResponseStillShows() async {
        let service = await fetchService([
            makeSurvey(id: 1, multipleResponses: true, alwaysVisible: true)
        ])
        service.markSurveyCompleted(service.allSurveys[0])
        // Multiple-response always-visible surveys re-appear after completion.
        expect(service.findSurveyForMap()?.id).to(equal(1))
    }

    // `markSurveyForLater` is self-contained: it defers the survey at the
    // `findSurvey` level (no dependency on the global reminder gate). The
    // deferred survey is hidden until it is due to reappear.
    func test_markSurveyForLater_hidesSurveyUntilDue() async {
        let service = await fetchService([makeSurvey(id: 1)])
        expect(service.findSurveyForMap()?.id).to(equal(1))

        service.markSurveyForLater(service.allSurveys[0])
        expect(service.findSurveyForMap()).to(beNil())

        // Still deferred on the next launch...
        store.incrementAppLaunchCount()
        expect(service.findSurveyForMap()).to(beNil())
    }

    func test_markSurveyForLater_reappearsAfterThreeLaunches() async {
        let service = await fetchService([makeSurvey(id: 1)])
        service.markSurveyForLater(service.allSurveys[0])
        expect(service.findSurveyForMap()).to(beNil())

        store.incrementAppLaunchCount()
        store.incrementAppLaunchCount()
        store.incrementAppLaunchCount()
        expect(service.findSurveyForMap()?.id).to(equal(1))
    }

    // MARK: - Fetch state ---------------------------------------------------

    func test_fetchSurveys_successAfterFailure_clearsLastError() async {
        let userID = store.surveyUserIdentifier
        let mockLoader = MockDataLoader(testName: name)

        // First fetch fails.
        let url = URL(string: "https://onebusaway.co/api/v1/regions/1/surveys.json?user_id=\(userID)")!
        let failResponse = MockDataResponse(
            data: Data(),
            urlResponse: mockLoader.buildURLResponse(URL: url, statusCode: 500),
            error: nil
        ) { $0.url?.host == url.host && $0.url?.path == url.path }
        mockLoader.mock(response: failResponse)

        let service = SurveyService(apiService: buildREST(mockLoader), userDataStore: store)
        await service.fetchSurveys()
        expect(service.lastError).toNot(beNil())

        // Then a forced fetch succeeds and the error is cleared.
        mockLoader.removeMappedResponses()
        mockLoader.mock(URLString: url.absoluteString, with: encode([makeSurvey(id: 1)]))
        await service.fetchSurveys(force: true)

        expect(service.lastError).to(beNil())
        expect(service.allSurveys.map(\.id)).to(equal([1]))
        expect(service.isLoading).to(beFalse())
    }

    // SUSPECTED INEFFICIENCY: an empty (but successful) response leaves
    // `allSurveys` empty, which makes the staleness cooldown a no-op — every
    // subsequent `fetchSurveys()` hits the network again. Pinned as behavior:
    // a non-forced re-fetch after an empty response *does* run and can pick up
    // newly-published surveys immediately (no 5-minute wait).
    func test_fetchSurveys_emptyResponse_doesNotEngageCooldown_characterization() async {
        let userID = store.surveyUserIdentifier
        let mockLoader = MockDataLoader(testName: name)
        let urlString = "https://onebusaway.co/api/v1/regions/1/surveys.json?user_id=\(userID)"

        mockLoader.mock(URLString: urlString, with: encode([]))
        let service = SurveyService(apiService: buildREST(mockLoader), userDataStore: store)
        await service.fetchSurveys()
        expect(service.allSurveys).to(beEmpty())

        // Without force, a second fetch still runs because allSurveys is empty.
        mockLoader.removeMappedResponses()
        mockLoader.mock(URLString: urlString, with: encode([makeSurvey(id: 1)]))
        await service.fetchSurveys()

        expect(service.allSurveys.map(\.id)).to(equal([1]))
    }

    // MARK: - Helpers -------------------------------------------------------

    private func hoursAgo(_ h: Double) -> Date { Date().addingTimeInterval(-3600 * h) }
    private func hoursFromNow(_ h: Double) -> Date { Date().addingTimeInterval(3600 * h) }

    private func buildREST(_ loader: MockDataLoader) -> RESTAPIService {
        let config = APIServiceConfiguration(
            baseURL: baseURL, apiKey: apiKey, uuid: uuid, appVersion: appVersion,
            regionIdentifier: pugetSoundRegionIdentifier, surveyBaseURL: surveyBaseURL
        )
        return RESTAPIService(config, dataLoader: loader)
    }

    private func encode(_ surveys: [Survey]) -> Data {
        let response = StudyResponse(surveys: surveys, region: SurveyRegion(id: 1, name: "Test"))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try! encoder.encode(response) // swiftlint:disable:this force_try
    }

    /// Builds a `SurveyService`, mocks the surveys endpoint with `surveys`,
    /// fetches, and returns the populated service.
    private func fetchService(_ surveys: [Survey]) async -> SurveyService {
        let mockLoader = MockDataLoader(testName: name)
        let userID = store.surveyUserIdentifier
        mockLoader.mock(
            URLString: "https://onebusaway.co/api/v1/regions/1/surveys.json?user_id=\(userID)",
            with: encode(surveys)
        )
        let service = SurveyService(apiService: buildREST(mockLoader), userDataStore: store)
        await service.fetchSurveys()
        return service
    }

    // Defaults are concrete (active) dates rather than `nil`, so callers can
    // pass an explicit `nil` to mean "open-ended" without it being overwritten.
    private func makeSurvey(
        id: Int = 1,
        showOnMap: Bool = true,
        showOnStops: Bool = true,
        startDate: Date? = Date().addingTimeInterval(-3600),
        endDate: Date? = Date().addingTimeInterval(3600),
        stopList: [String]? = nil,
        routesList: [String]? = nil,
        multipleResponses: Bool = false,
        alwaysVisible: Bool = false,
        questions: [SurveyQuestion]? = nil
    ) -> Survey {
        Survey(
            id: id,
            name: "Survey \(id)",
            createdAt: Date(),
            updatedAt: Date(),
            showOnMap: showOnMap,
            showOnStops: showOnStops,
            startDate: startDate,
            endDate: endDate,
            visibleStopsList: stopList,
            visibleRoutesList: routesList,
            allowsMultipleResponses: multipleResponses,
            alwaysVisible: alwaysVisible,
            study: Study(id: 1, name: "Study", description: nil),
            questions: questions ?? makeQuestions()
        )
    }

    private func makeQuestions(count: Int = 2) -> [SurveyQuestion] {
        (0..<count).map { index in
            SurveyQuestion(
                id: index + 1,
                position: index + 1,
                required: false,
                content: QuestionContent(labelText: "Q\(index + 1)", type: .text)
            )
        }
    }
}
