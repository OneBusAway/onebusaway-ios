//
//  SurveyServicePrioritizationTests.swift
//  OBAKitTests
//
//  Created by Mohamed Sliem on 06/12/2025.
//

import XCTest
import Nimble
@testable import OBAKitCore

@MainActor
final class SurveyServicePrioritizationTests: OBATestCase {

    nonisolated(unsafe) private var surveyService: SurveyService!
    nonisolated(unsafe) private var testUserDefaults: UserDefaults!
    nonisolated(unsafe) private var testUserDataStore: UserDefaultsStore!

    override func setUp() {
        super.setUp()
        testUserDefaults = buildUserDefaults(suiteName: "\(userDefaultsSuiteName).prioritization")
        testUserDefaults.removePersistentDomain(forName: "\(userDefaultsSuiteName).prioritization")
        testUserDataStore = UserDefaultsStore(userDefaults: testUserDefaults)
        surveyService = SurveyService(apiService: nil, userDataStore: testUserDataStore)
    }

    override func tearDown() {
        testUserDefaults.removePersistentDomain(forName: "\(userDefaultsSuiteName).prioritization")
        super.tearDown()
    }

    // MARK: - Helpers

    private func buildServiceWithSurveys(_ surveys: [Survey], userDataStore: UserDefaultsStore? = nil) -> SurveyService {
        let store = userDataStore ?? testUserDataStore!
        let mockLoader = MockDataLoader(testName: name)

        let studyResponse = StudyResponse(
            surveys: surveys,
            region: SurveyRegion(id: 1, name: "Test")
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode(studyResponse) // swiftlint:disable:this force_try

        let userID = store.surveyUserIdentifier
        mockLoader.mock(
            URLString: "https://onebusaway.co/api/v1/regions/1/surveys.json?user_id=\(userID)",
            with: data
        )

        let config = APIServiceConfiguration(
            baseURL: baseURL,
            apiKey: apiKey,
            uuid: uuid,
            appVersion: appVersion,
            regionIdentifier: pugetSoundRegionIdentifier,
            surveyBaseURL: surveyBaseURL
        )
        let apiService = RESTAPIService(config, dataLoader: mockLoader)
        let service = SurveyService(apiService: apiService, userDataStore: store)
        return service
    }

    private func fetchAndReturnService(surveys: [Survey], userDataStore: UserDefaultsStore? = nil) async -> SurveyService {
        let service = buildServiceWithSurveys(surveys, userDataStore: userDataStore)
        await service.fetchSurveys()
        return service
    }

    // MARK: - Empty/No Questions

    func test_findSurveyForMap_whenEmpty_returnsNil() async {
        let service = await fetchAndReturnService(surveys: [])
        let result = service.findSurveyForMap()
        expect(result).to(beNil())
    }

    func test_findSurveyForStop_whenNoQuestions_returnsNil() async {
        let surveys = [
            makeSurvey(id: 0, showOnStops: false),
            makeSurvey(id: 1, showOnMap: false),
        ]
        let service = await fetchAndReturnService(surveys: surveys)
        let result = service.findSurveyForStop(stopID: "STOP_A", routeIDs: [])
        expect(result).to(beNil())
    }

    // MARK: - Map Context

    func test_findSurveyForMap_returnsMapVisibleSurvey() async {
        let surveys = [
            makeSurvey(id: 0, showOnStops: false),
            makeSurvey(id: 1, showOnMap: false),
            makeSurvey(id: 2, questions: makeQuestions())
        ]
        let service = await fetchAndReturnService(surveys: surveys)
        let result = service.findSurveyForMap()
        expect(result?.id).to(equal(2))
    }

    func test_findSurveyForMap_returnsFirstVisible() async {
        let surveys = [
            makeSurvey(id: 0, showOnStops: false, questions: makeQuestions(count: 5)),
            makeSurvey(id: 1, showOnMap: false, questions: makeQuestions(count: 4)),
            makeSurvey(id: 2, showOnStops: false, questions: makeQuestions())
        ]
        let service = await fetchAndReturnService(surveys: surveys)
        let result = service.findSurveyForMap()
        expect(result?.id).to(equal(0))
    }

    func test_findSurveyForMap_whenNoMapVisible_returnsNil() async {
        let surveys = [
            makeSurvey(id: 0, showOnMap: false, questions: makeQuestions()),
            makeSurvey(id: 1, showOnMap: false, questions: makeQuestions()),
        ]
        let service = await fetchAndReturnService(surveys: surveys)
        let result = service.findSurveyForMap()
        expect(result).to(beNil())
    }

    // MARK: - Stop Context

    func test_findSurveyForStop_returnsStopVisibleSurvey() async {
        let surveys = [
            makeSurvey(id: 0, showOnStops: false, questions: makeQuestions()),
            makeSurvey(id: 1, questions: makeQuestions()),
        ]
        let service = await fetchAndReturnService(surveys: surveys)
        let result = service.findSurveyForStop(stopID: "STOP_A", routeIDs: [])
        expect(result?.id).to(equal(1))
    }

    func test_findSurveyForStop_matchesStopInList() async {
        let surveys = [
            makeSurvey(id: 0, stopList: ["STOP_A", "STOP_B"], questions: makeQuestions()),
            makeSurvey(id: 1, stopList: ["STOP_C"], questions: makeQuestions()),
        ]
        let service = await fetchAndReturnService(surveys: surveys)
        let result = service.findSurveyForStop(stopID: "STOP_C", routeIDs: [])
        expect(result?.id).to(equal(1))
    }

    func test_findSurveyForStop_matchesRouteID() async {
        let surveys = [
            makeSurvey(id: 0, stopList: ["STOP_X"], routesList: ["1_300"], questions: makeQuestions()),
            makeSurvey(id: 1, stopList: ["STOP_X"], routesList: ["1_309"], questions: makeQuestions()),
        ]
        let service = await fetchAndReturnService(surveys: surveys)
        let result = service.findSurveyForStop(stopID: "STOP_D", routeIDs: ["1_309", "1_315"])
        expect(result?.id).to(equal(1))
    }

    func test_findSurveyForStop_noMatch_returnsNil() async {
        let surveys = [
            makeSurvey(id: 0, stopList: ["STOP_A"], routesList: ["1_300"], questions: makeQuestions()),
        ]
        let service = await fetchAndReturnService(surveys: surveys)
        let result = service.findSurveyForStop(stopID: "STOP_Z", routeIDs: ["1_999"])
        expect(result).to(beNil())
    }

    // MARK: - Priority: Always Visible

    func test_alwaysVisible_notCompleted_returnedImmediately() async {
        let store = UserDefaultsStore(userDefaults: testUserDefaults)
        let userID = store.surveyUserIdentifier
        store.markSurveyCompleted(surveyId: 0, userIdentifier: userID)

        let surveys = [
            makeSurvey(id: 0, questions: makeQuestions()),
            makeSurvey(id: 1, alwaysVisible: true, questions: makeQuestions()),
            makeSurvey(id: 2, multipleResponses: true, alwaysVisible: true, questions: makeQuestions())
        ]
        let service = await fetchAndReturnService(surveys: surveys, userDataStore: store)
        let result = service.findSurveyForMap()
        expect(result?.id).to(equal(1))
    }

    func test_alwaysVisible_allCompleted_returnsNil() async {
        let store = UserDefaultsStore(userDefaults: testUserDefaults)
        let userID = store.surveyUserIdentifier
        store.markSurveyCompleted(surveyId: 0, userIdentifier: userID)
        store.markSurveyCompleted(surveyId: 1, userIdentifier: userID)

        let surveys = [
            makeSurvey(id: 0, alwaysVisible: true, questions: makeQuestions()),
            makeSurvey(id: 1, alwaysVisible: true, questions: makeQuestions()),
        ]
        let service = await fetchAndReturnService(surveys: surveys, userDataStore: store)
        let result = service.findSurveyForMap()
        expect(result).to(beNil())
    }

    // MARK: - Priority: Multiple Responses

    func test_multipleResponses_returnsEvenWhenCompleted() async {
        let store = UserDefaultsStore(userDefaults: testUserDefaults)
        let userID = store.surveyUserIdentifier
        store.markSurveyCompleted(surveyId: 0, userIdentifier: userID)
        store.markSurveyCompleted(surveyId: 1, userIdentifier: userID)

        let surveys = [
            makeSurvey(id: 0, alwaysVisible: true, questions: makeQuestions()),
            makeSurvey(id: 1, multipleResponses: true, alwaysVisible: true, questions: makeQuestions()),
        ]
        let service = await fetchAndReturnService(surveys: surveys, userDataStore: store)
        let result = service.findSurveyForMap()
        expect(result?.id).to(equal(1))
    }

    // MARK: - Priority: One-Time Incomplete

    func test_oneTimeIncomplete_prioritizedOverMultipleResponses() async {
        let surveys = [
            makeSurvey(id: 0, multipleResponses: true, alwaysVisible: true, questions: makeQuestions()),
            makeSurvey(id: 1, questions: makeQuestions()),
        ]
        let service = await fetchAndReturnService(surveys: surveys)
        let result = service.findSurveyForMap()
        // One-time incomplete (id:1) should be prioritized over multiple-response (id:0)
        expect(result?.id).to(equal(1))
    }

    func test_allCompleted_regularSurveys_returnsNil() async {
        let store = UserDefaultsStore(userDefaults: testUserDefaults)
        let userID = store.surveyUserIdentifier
        store.markSurveyCompleted(surveyId: 0, userIdentifier: userID)
        store.markSurveyCompleted(surveyId: 1, userIdentifier: userID)

        let surveys = [
            makeSurvey(id: 0, questions: makeQuestions()),
            makeSurvey(id: 1, questions: makeQuestions()),
        ]
        let service = await fetchAndReturnService(surveys: surveys, userDataStore: store)
        let result = service.findSurveyForMap()
        expect(result).to(beNil())
    }

    // MARK: - Mark For Later

    func test_markedForLater_showsAgainAtCorrectLaunchCount() async {
        let store = UserDefaultsStore(userDefaults: testUserDefaults)
        let userID = store.surveyUserIdentifier
        store.markSurveyCompleted(surveyId: 0, userIdentifier: userID)
        store.markSurveyForLater(surveyId: 0, userIdentifier: userID)

        // Simulate 3 more app launches
        store.incrementAppLaunchCount()
        store.incrementAppLaunchCount()
        store.incrementAppLaunchCount()

        let surveys = [
            makeSurvey(id: 0, questions: makeQuestions()),
        ]
        let service = await fetchAndReturnService(surveys: surveys, userDataStore: store)
        let result = service.findSurveyForMap()
        expect(result?.id).to(equal(0))
    }
}

// MARK: - Helpers
extension SurveyServicePrioritizationTests {

    func makeSurvey(
        id: Int = 1,
        name: String = "Survey",
        showOnMap: Bool = true,
        showOnStops: Bool = true,
        stopList: [String]? = nil,
        routesList: [String]? = nil,
        multipleResponses: Bool = false,
        alwaysVisible: Bool = false,
        study: Study? = nil,
        questions: [SurveyQuestion] = []
    ) -> Survey {
        let studyModel = study ?? Study(id: 1, name: "Study", description: "Description")

        return .init(
            id: id,
            name: name,
            createdAt: Date(),
            updatedAt: Date(),
            showOnMap: showOnMap,
            showOnStops: showOnStops,
            startDate: Date().addingTimeInterval(-3600),
            endDate: Date().addingTimeInterval(3600),
            visibleStopsList: stopList,
            visibleRoutesList: routesList,
            allowsMultipleResponses: multipleResponses,
            alwaysVisible: alwaysVisible,
            study: studyModel,
            questions: questions
        )
    }

    func makeQuestions(count: Int = 3) -> [SurveyQuestion] {
        (0..<count).map { index in
            SurveyQuestion(
                id: index + 1,
                position: index,
                required: false,
                content: QuestionContent(
                    labelText: "Question \(index + 1)",
                    type: .text
                )
            )
        }
    }
}
