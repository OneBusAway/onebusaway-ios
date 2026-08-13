//
//  SurveyServiceAppearanceTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

@Suite(.serialized)
final class SurveyServiceAppearanceTests: OBATestCase {

    nonisolated(unsafe) private var testUserDefaults: UserDefaults!
    nonisolated(unsafe) private var store: UserDefaultsStore!

    override init() async throws {
        try await super.init()

        testUserDefaults = buildUserDefaults(suiteName: "\(userDefaultsSuiteName).appearance")
        testUserDefaults.removePersistentDomain(forName: "\(userDefaultsSuiteName).appearance")
        store = UserDefaultsStore(userDefaults: testUserDefaults)
    }

    isolated deinit {
        testUserDefaults.removePersistentDomain(forName: "\(userDefaultsSuiteName).appearance")
    }

    // MARK: - visibleSurveys filtering (date activity) ----------------------

    @Test func `Fetch mixed active and expired visible surveys excludes expired`() async {
        let service = await fetchService([
            makeSurvey(id: 1),                                   // active
            makeSurvey(id: 2, startDate: hoursAgo(2), endDate: hoursAgo(1)), // expired
            makeSurvey(id: 3, startDate: hoursFromNow(1), endDate: hoursFromNow(2)) // future
        ])

        #expect(service.allSurveys.count == 3)
        #expect(service.visibleSurveys.map(\.id) == [1])
    }

    @Test func `Fetch all inactive visible empty and find returns nil`() async {
        let service = await fetchService([
            makeSurvey(id: 1, showOnStops: true, startDate: hoursAgo(2), endDate: hoursAgo(1)),
            makeSurvey(id: 2, showOnStops: true, startDate: hoursFromNow(1), endDate: hoursFromNow(2))
        ])

        #expect(service.allSurveys.count == 2)
        #expect(service.visibleSurveys.isEmpty)
        #expect(service.findSurveyForMap() == nil)
        #expect(service.findSurveyForStop(stopID: "STOP_A", routeIDs: ["R1"]) == nil)
    }

    @Test func `Fetch survey with open ended dates is active`() async {
        // nil start + nil end => always within range.
        let service = await fetchService([makeSurvey(id: 1, startDate: nil, endDate: nil)])
        #expect(service.findSurveyForMap()?.id == 1)
    }

    // MARK: - Stop targeting matrix ----------------------------------------

    @Test func `Find survey for stop nil stop list nil route list shows at any stop`() async {
        let service = await fetchService([
            makeSurvey(id: 1, showOnStops: true, stopList: nil, routesList: nil)
        ])
        #expect(service.findSurveyForStop(stopID: "ANY_STOP", routeIDs: []).map(\.id) == 1)
    }

    @Test func `Find survey for stop stop in list shows`() async {
        let service = await fetchService([
            makeSurvey(id: 1, showOnStops: true, stopList: ["STOP_A", "STOP_B"])
        ])
        #expect(service.findSurveyForStop(stopID: "STOP_B", routeIDs: []).map(\.id) == 1)
    }

    @Test func `Find survey for stop stop not in list route matches shows`() async {
        let service = await fetchService([
            makeSurvey(id: 1, showOnStops: true, stopList: ["STOP_A"], routesList: ["R9"])
        ])
        // The stop is not listed, but one of its routes is.
        #expect(service.findSurveyForStop(stopID: "STOP_Z", routeIDs: ["R9"]).map(\.id) == 1)
    }

    @Test func `Find survey for stop stop not in list route not in list returns nil`() async {
        let service = await fetchService([
            makeSurvey(id: 1, showOnStops: true, stopList: ["STOP_A"], routesList: ["R9"])
        ])
        #expect(service.findSurveyForStop(stopID: "STOP_Z", routeIDs: ["R1"]) == nil)
    }

    @Test func `Find survey for stop show on stops false returns nil`() async {
        let service = await fetchService([
            makeSurvey(id: 1, showOnMap: true, showOnStops: false)
        ])
        #expect(service.findSurveyForStop(stopID: "STOP_A", routeIDs: ["R1"]) == nil)
    }

    // An empty stop/route list means "no restriction" — identical to nil — so a
    // stops-enabled survey with both lists empty appears on every stop,
    // regardless of the stop's routes.
    @Test func `Find survey for stop empty stop and route lists shows at any stop`() async {
        let service = await fetchService([
            makeSurvey(id: 1, showOnStops: true, stopList: [], routesList: [])
        ])
        #expect(service.findSurveyForStop(stopID: "STOP_A", routeIDs: ["R1"]).map(\.id) == 1)
        #expect(service.findSurveyForStop(stopID: "STOP_OTHER", routeIDs: []).map(\.id) == 1)
    }

    // A survey scoped to a specific stop list with no route targeting (nil/empty
    // route list) must NOT leak onto stops outside its list. A nil/empty route
    // list means "no route-based targeting" — it contributes nothing — not
    // "every route".
    @Test func `Find survey for stop stop scoped nil route list does not leak to unlisted stop`() async {
        let service = await fetchService([
            makeSurvey(id: 1, showOnStops: true, stopList: ["STOP_A"], routesList: nil)
        ])
        // Listed stop: shows.
        #expect(service.findSurveyForStop(stopID: "STOP_A", routeIDs: ["R1"]).map(\.id) == 1)
        // Unlisted stop must not match, regardless of the stop's routes.
        #expect(service.findSurveyForStop(stopID: "STOP_Z", routeIDs: ["R1"]) == nil)
        #expect(service.findSurveyForStop(stopID: "STOP_Z", routeIDs: []) == nil)
    }

    @Test func `Find survey for stop route scoped nil stop list shows only on served stops`() async {
        let service = await fetchService([
            makeSurvey(id: 1, showOnStops: true, stopList: nil, routesList: ["R9"])
        ])
        // Any stop served by R9 shows it...
        #expect(service.findSurveyForStop(stopID: "STOP_A", routeIDs: ["R9"]).map(\.id) == 1)
        #expect(service.findSurveyForStop(stopID: "STOP_B", routeIDs: ["R9", "R1"]).map(\.id) == 1)
        // ...stops not served by R9 do not.
        #expect(service.findSurveyForStop(stopID: "STOP_A", routeIDs: ["R1"]) == nil)
    }

    // MARK: - Map targeting -------------------------------------------------

    @Test func `Find survey for map show on map false returns nil`() async {
        let service = await fetchService([
            makeSurvey(id: 1, showOnMap: false, showOnStops: true)
        ])
        #expect(service.findSurveyForMap() == nil)
    }

    @Test func `Find survey for map skips stop only survey returns map survey`() async {
        let service = await fetchService([
            makeSurvey(id: 1, showOnMap: false, showOnStops: true),
            makeSurvey(id: 2, showOnMap: true, showOnStops: false)
        ])
        #expect(service.findSurveyForMap()?.id == 2)
    }

    // MARK: - Empty-question gating ----------------------------------------

    @Test func `Find survey skips survey with no questions returns next valid survey`() async {
        let service = await fetchService([
            makeSurvey(id: 1, questions: []),                  // no questions -> skipped
            makeSurvey(id: 2, questions: makeQuestions())      // valid
        ])
        #expect(service.findSurveyForMap()?.id == 2)
    }

    @Test func `Find survey only survey has no questions returns nil`() async {
        let service = await fetchService([makeSurvey(id: 1, questions: [])])
        #expect(service.findSurveyForMap() == nil)
    }

    // MARK: - Priority ordering --------------------------------------------

    // Always-visible single-response surveys are documented as the highest
    // priority and are returned immediately — even when an incomplete one-time
    // survey appears earlier in the list. This pins that ordering contract.
    @Test func `Priority always visible single beats earlier one time`() async {
        let service = await fetchService([
            makeSurvey(id: 1),                          // one-time, incomplete (earlier)
            makeSurvey(id: 2, alwaysVisible: true)      // always-visible single (later)
        ])
        #expect(service.findSurveyForMap()?.id == 2)
    }

    @Test func `Priority completed always visible single falls through to one time`() async {
        let userID = store.surveyUserIdentifier
        store.markSurveyCompleted(surveyId: 2, userIdentifier: userID)

        let service = await fetchService([
            makeSurvey(id: 1),                          // one-time, incomplete
            makeSurvey(id: 2, alwaysVisible: true)      // always-visible single, completed
        ])
        // The always-visible single is exhausted, so the one-time wins.
        #expect(service.findSurveyForMap()?.id == 1)
    }

    @Test func `Priority one time incomplete beats always visible multi`() async {
        let service = await fetchService([
            makeSurvey(id: 1, multipleResponses: true, alwaysVisible: true), // lowest priority
            makeSurvey(id: 2)                                                 // one-time incomplete
        ])
        #expect(service.findSurveyForMap()?.id == 2)
    }

    // MARK: - Completion / dismissal ---------------------------------------

    @Test func `Dismiss survey hides one time survey`() async {
        let service = await fetchService([makeSurvey(id: 1)])
        #expect(service.findSurveyForMap()?.id == 1)

        service.dismissSurvey(service.allSurveys[0])
        #expect(service.findSurveyForMap() == nil)
    }

    @Test func `Mark completed hides one time but multi response still shows`() async {
        let service = await fetchService([
            makeSurvey(id: 1, multipleResponses: true, alwaysVisible: true)
        ])
        service.markSurveyCompleted(service.allSurveys[0])
        // Multiple-response always-visible surveys re-appear after completion.
        #expect(service.findSurveyForMap()?.id == 1)
    }

    // `markSurveyForLater` is self-contained: it defers the survey at the
    // `findSurvey` level (no dependency on the global reminder gate). The
    // deferred survey is hidden until it is due to reappear.
    @Test func `Mark survey for later hides survey until due`() async {
        let service = await fetchService([makeSurvey(id: 1)])
        #expect(service.findSurveyForMap()?.id == 1)

        service.markSurveyForLater(service.allSurveys[0])
        #expect(service.findSurveyForMap() == nil)

        // Still deferred on the next launch...
        store.incrementAppLaunchCount()
        #expect(service.findSurveyForMap() == nil)
    }

    @Test func `Mark survey for later reappears after three launches`() async {
        let service = await fetchService([makeSurvey(id: 1)])
        service.markSurveyForLater(service.allSurveys[0])
        #expect(service.findSurveyForMap() == nil)

        store.incrementAppLaunchCount()
        store.incrementAppLaunchCount()
        store.incrementAppLaunchCount()
        #expect(service.findSurveyForMap()?.id == 1)
    }

    // MARK: - Fetch state ---------------------------------------------------

    @Test func `Fetch surveys success after failure clears last error`() async {
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
        #expect(service.lastError != nil)

        // Then a forced fetch succeeds and the error is cleared.
        mockLoader.removeMappedResponses()
        mockLoader.mock(URLString: url.absoluteString, with: encode([makeSurvey(id: 1)]))
        await service.fetchSurveys(force: true)

        #expect(service.lastError == nil)
        #expect(service.allSurveys.map(\.id) == [1])
        #expect(!service.isLoading)
    }

    // SUSPECTED INEFFICIENCY: an empty (but successful) response leaves
    // `allSurveys` empty, which makes the staleness cooldown a no-op — every
    // subsequent `fetchSurveys()` hits the network again. Pinned as behavior:
    // a non-forced re-fetch after an empty response *does* run and can pick up
    // newly-published surveys immediately (no 5-minute wait).
    @Test func `Fetch surveys empty response does not engage cooldown characterization`() async {
        let userID = store.surveyUserIdentifier
        let mockLoader = MockDataLoader(testName: name)
        let urlString = "https://onebusaway.co/api/v1/regions/1/surveys.json?user_id=\(userID)"

        mockLoader.mock(URLString: urlString, with: encode([]))
        let service = SurveyService(apiService: buildREST(mockLoader), userDataStore: store)
        await service.fetchSurveys()
        #expect(service.allSurveys.isEmpty)

        // Without force, a second fetch still runs because allSurveys is empty.
        mockLoader.removeMappedResponses()
        mockLoader.mock(URLString: urlString, with: encode([makeSurvey(id: 1)]))
        await service.fetchSurveys()

        #expect(service.allSurveys.map(\.id) == [1])
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
