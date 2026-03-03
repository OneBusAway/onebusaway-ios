//
//  SurveyServiceStateTests.swift
//  OBAKitTests
//
//  Created by Mohamed Sliem on 13/12/2025.
//

import XCTest
import Nimble
@testable import OBAKitCore

@MainActor
final class SurveyServiceStateTests: OBATestCase {

    nonisolated(unsafe) private var surveyService: SurveyService!
    nonisolated(unsafe) private var testUserDefaults: UserDefaults!
    nonisolated(unsafe) private var testUserDataStore: UserDefaultsStore!

    override func setUp() {
        super.setUp()
        testUserDefaults = buildUserDefaults(suiteName: "\(userDefaultsSuiteName).state")
        testUserDefaults.removePersistentDomain(forName: "\(userDefaultsSuiteName).state")
        testUserDataStore = UserDefaultsStore(userDefaults: testUserDefaults)
        surveyService = SurveyService(apiService: nil, userDataStore: testUserDataStore)
    }

    override func tearDown() {
        testUserDefaults.removePersistentDomain(forName: "\(userDefaultsSuiteName).state")
        super.tearDown()
    }

    // MARK: - shouldShowSurvey

    func test_shouldShowSurvey_returnsFalse_whenFeatureDisabled() {
        testUserDataStore.isSurveyEnabled = false
        // Even with correct launch count, disabled means no survey
        setAppLaunchCount(3)

        let result = surveyService.shouldShowSurvey()
        expect(result).to(beFalse())
    }

    func test_shouldShowSurvey_returnsFalse_whenAppLaunchIsZero() {
        testUserDataStore.isSurveyEnabled = true
        setAppLaunchCount(0)

        let result = surveyService.shouldShowSurvey()
        expect(result).to(beFalse())
    }

    func test_shouldShowSurvey_returnsFalse_whenLaunchCountNotMultipleOfThree() {
        testUserDataStore.isSurveyEnabled = true
        setAppLaunchCount(4)

        let result = surveyService.shouldShowSurvey()
        expect(result).to(beFalse())
    }

    func test_shouldShowSurvey_returnsTrue_whenLaunchCountIsMultipleOfThree() {
        testUserDataStore.isSurveyEnabled = true
        setAppLaunchCount(6)

        let result = surveyService.shouldShowSurvey()
        expect(result).to(beTrue())
    }

    func test_shouldShowSurvey_returnsFalse_whenNextReminderDateIsInFuture() {
        testUserDataStore.isSurveyEnabled = true
        setAppLaunchCount(6)
        testUserDataStore.nextSurveyReminderDate = Date().addingTimeInterval(3600)

        let result = surveyService.shouldShowSurvey()
        expect(result).to(beFalse())
    }

    func test_shouldShowSurvey_returnsTrue_whenNextReminderDateIsInPast() {
        testUserDataStore.isSurveyEnabled = true
        setAppLaunchCount(6)
        testUserDataStore.nextSurveyReminderDate = Date().addingTimeInterval(-300)

        let result = surveyService.shouldShowSurvey()
        expect(result).to(beTrue())
    }

    func test_shouldShowSurvey_returnsTrue_whenReminderDateIsNil() {
        testUserDataStore.isSurveyEnabled = true
        setAppLaunchCount(6)
        testUserDataStore.nextSurveyReminderDate = nil

        let result = surveyService.shouldShowSurvey()
        expect(result).to(beTrue())
    }

    // MARK: - setNextReminderDate

    func test_setNextReminderDate_setsDateThreeDaysAhead() {
        let now = Date()

        surveyService.setNextReminderDate()

        let storedDate = testUserDataStore.nextSurveyReminderDate
        expect(storedDate).toNot(beNil())

        let diff = Calendar.current.dateComponents([.day], from: now, to: storedDate!).day
        expect(diff).to(equal(3))
    }

    func test_setNextReminderDate_overwritesExistingDate() {
        testUserDataStore.nextSurveyReminderDate = Date().addingTimeInterval(-50)

        surveyService.setNextReminderDate()

        let newDate = testUserDataStore.nextSurveyReminderDate
        expect(newDate).toNot(beNil())
        expect(newDate).to(beGreaterThan(Date()))
    }

    // MARK: - markSurveyCompleted

    func test_markSurveyCompleted_tracksSurvey() {
        let survey = makeSurvey(id: 7)
        surveyService.markSurveyCompleted(survey)

        let userID = testUserDataStore.surveyUserIdentifier
        expect(self.testUserDataStore.isSurveyCompleted(surveyId: 7, userIdentifier: userID)).to(beTrue())
    }

    // MARK: - markSurveyForLater

    func test_markSurveyForLater_tracksSurvey() {
        let survey = makeSurvey(id: 9)
        surveyService.markSurveyForLater(survey)

        let userID = testUserDataStore.surveyUserIdentifier
        // Immediately after marking, shouldShowSurveyLater returns false (0 launches since marking)
        expect(self.testUserDataStore.shouldShowSurveyLater(surveyId: 9, userIdentifier: userID)).to(beFalse())
    }

    // MARK: - Combined Behavior

    func test_shouldShowSurvey_minimumValidCase() {
        testUserDataStore.isSurveyEnabled = true
        setAppLaunchCount(3)

        expect(self.surveyService.shouldShowSurvey()).to(beTrue())
    }

    func test_shouldShowSurvey_whenLaunchIsThirdButFeatureDisabled_returnsFalse() {
        testUserDataStore.isSurveyEnabled = false
        setAppLaunchCount(3)

        expect(self.surveyService.shouldShowSurvey()).to(beFalse())
    }

    // MARK: - formatCheckboxAnswer

    func test_formatCheckboxAnswer_normalCase() {
        let result = surveyService.formatCheckboxAnswer(["Option A", "Option B"])
        expect(result).to(equal("[\"Option A\",\"Option B\"]"))
    }

    func test_formatCheckboxAnswer_emptyArray() {
        let result = surveyService.formatCheckboxAnswer([])
        expect(result).to(equal("[]"))
    }

    func test_formatCheckboxAnswer_singleItem() {
        let result = surveyService.formatCheckboxAnswer(["Only"])
        expect(result).to(equal("[\"Only\"]"))
    }

    // MARK: - createQuestionResponse

    func test_createQuestionResponse_returnsCorrectFields() {
        let question = SurveyQuestion(
            id: 42,
            position: 1,
            required: true,
            content: QuestionContent(labelText: "How are you?", type: .text)
        )

        let response = surveyService.createQuestionResponse(question: question, answer: "Great")

        expect(response.questionId).to(equal(42))
        expect(response.questionType).to(equal("text"))
        expect(response.questionLabel).to(equal("How are you?"))
        expect(response.answer).to(equal("Great"))
    }

    func test_createQuestionResponse_radioType() {
        let question = SurveyQuestion(
            id: 10,
            position: 2,
            required: false,
            content: QuestionContent(labelText: "Pick one", type: .radio, options: ["A", "B"])
        )

        let response = surveyService.createQuestionResponse(question: question, answer: "A")

        expect(response.questionType).to(equal("radio"))
        expect(response.questionLabel).to(equal("Pick one"))
    }

    // MARK: - Submit methods with nil apiService

    func test_submitHeroQuestion_nilApiService_throws() async {
        let survey = makeSurvey(id: 1, questions: makeQuestions())
        let response = surveyService.createQuestionResponse(
            question: survey.questions[0],
            answer: "test"
        )

        await expect {
            try await self.surveyService.submitHeroQuestion(
                survey: survey,
                heroQuestionResponse: response
            )
        }.to(throwError { error in
            if case APIError.surveyServiceNotConfigured = error {
                return
            }
            fail("Expected APIError.surveyServiceNotConfigured but got \(error)")
        })
    }

    func test_submitAdditionalQuestions_nilApiService_throws() async {
        await expect {
            try await self.surveyService.submitAdditionalQuestions(
                responseID: "some-id",
                additionalResponses: []
            )
        }.to(throwError { error in
            if case APIError.surveyServiceNotConfigured = error {
                return
            }
            fail("Expected APIError.surveyServiceNotConfigured but got \(error)")
        })
    }

    // MARK: - visibleSurveys re-filter on state changes

    func test_markSurveyCompleted_updatesVisibleSurveys() async {
        let service = await buildServiceWithLoadedSurveys()
        let initialVisible = service.visibleSurveys.count

        expect(initialVisible).to(beGreaterThan(0))

        // Marking a survey completed should trigger re-filter of visibleSurveys
        let survey = service.allSurveys.first!
        service.markSurveyCompleted(survey)

        // visibleSurveys should be refreshed (count stays same since isActive doesn't depend on completion)
        expect(service.visibleSurveys.count).to(equal(initialVisible))
    }

    func test_markSurveyForLater_updatesVisibleSurveys() async {
        let service = await buildServiceWithLoadedSurveys()
        let initialVisible = service.visibleSurveys.count

        expect(initialVisible).to(beGreaterThan(0))

        let survey = service.allSurveys.first!
        service.markSurveyForLater(survey)

        // visibleSurveys should be refreshed
        expect(service.visibleSurveys.count).to(equal(initialVisible))
    }

    // MARK: - Helpers

    private func setAppLaunchCount(_ count: Int) {
        for _ in 0..<count {
            testUserDataStore.incrementAppLaunchCount()
        }
    }

    private func makeSurvey(id: Int, questions: [SurveyQuestion] = []) -> Survey {
        Survey(
            id: id,
            name: "Survey \(id)",
            createdAt: Date(),
            updatedAt: Date(),
            showOnMap: true,
            showOnStops: true,
            startDate: nil,
            endDate: nil,
            visibleStopsList: nil,
            visibleRoutesList: nil,
            allowsMultipleResponses: false,
            allowsVisible: false,
            study: Study(id: 1, name: "Study", description: nil),
            questions: questions
        )
    }

    private func makeQuestions(count: Int = 3) -> [SurveyQuestion] {
        (0..<count).map { index in
            SurveyQuestion(
                id: index + 1,
                position: index,
                required: false,
                content: QuestionContent(labelText: "Question \(index + 1)", type: .text)
            )
        }
    }

    private func buildServiceWithLoadedSurveys() async -> SurveyService {
        let surveys = [
            makeSurvey(id: 1, questions: makeQuestions()),
            makeSurvey(id: 2, questions: makeQuestions()),
        ]

        let mockLoader = MockDataLoader(testName: name)
        let studyResponse = StudyResponse(
            surveys: surveys,
            region: SurveyRegion(id: 1, name: "Test")
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let entryData = try! encoder.encode(studyResponse)  // swiftlint:disable:this force_try
        let entryJSON = try! JSONSerialization.jsonObject(with: entryData)  // swiftlint:disable:this force_try

        let wrappedJSON: [String: Any] = [
            "code": 200,
            "text": "OK",
            "version": 2,
            "data": ["entry": entryJSON]
        ]
        let data = try! JSONSerialization.data(withJSONObject: wrappedJSON)  // swiftlint:disable:this force_try

        let userID = testUserDataStore.surveyUserIdentifier
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
        let service = SurveyService(apiService: apiService, userDataStore: testUserDataStore)
        await service.fetchSurveys()
        return service
    }
}
