//
//  SurveyServiceTests.swift
//  OBAKitTests
//
//  Created by Mohamed Sliem on 04/12/2025.
//

import XCTest
import Testing
@testable import OBAKitCore

final class SurveyServiceTests: OBATestCase {

    // MARK: - Helpers

    private var mockDataLoader: MockDataLoader!
    private var testRESTService: RESTAPIService!

    override func setUp() async throws {
        try await super.setUp()
        mockDataLoader = MockDataLoader(testName: name)
        let config = APIServiceConfiguration(
            baseURL: baseURL,
            apiKey: apiKey,
            uuid: uuid,
            appVersion: appVersion,
            regionIdentifier: pugetSoundRegionIdentifier,
            surveyBaseURL: surveyBaseURL
        )
        testRESTService = RESTAPIService(config, dataLoader: mockDataLoader)
    }

    // MARK: - GET Surveys

    private func loadSurveys() async throws -> StudyResponse {
        let data = Fixtures.loadData(file: "surveys_always_visible_one_time.json")

        mockDataLoader.mock(
            URLString: "https://onebusaway.co/api/v1/regions/1/surveys.json?user_id=12345-12345-12345-12345-12345",
            with: data
        )
        return try await testRESTService.getSurveys(userID: uuid)
    }

    func test_getSurveys_success_metadata() async throws {
        let response = try await loadSurveys()

        #expect(response.region.name == "Puget Sound")
        #expect(response.region.id == 1)

        #expect(response.surveys.count == 5)
    }

    func test_firstSurvey_basicProperties() async throws {
        let response = try await loadSurveys()
        let survey = response.surveys.first

        #expect(survey != nil)

        #expect(survey?.id == 1)
        #expect(survey?.name == "Always Visible — One-Time")
        #expect(survey?.showOnMap == true)
        #expect(survey?.showOnStops == true)
        #expect(survey?.alwaysVisible == true)
        #expect(survey?.allowsMultipleResponses == false)

        #expect(survey?.visibleStopsList?.count == 2)
        #expect(survey?.visibleRoutesList?.count == 2)
        #expect(survey?.questions.count == 5)
    }

    func test_firstSurvey_questionDecoding() async throws {
        let response = try await loadSurveys()
        let survey = response.surveys.first!

        let questions = survey.questions
        #expect(questions.count == 5)

        // Q1: text
        let q1 = questions[0]
        #expect(q1.content.type == .text)
        #expect(q1.content.labelText == "Do you like OBA IOS App ?")

        // Q2: radio
        let q2 = questions[1]
        #expect(q2.content.type == .radio)
        #expect(q2.content.options == ["Yes", "No"])

        // Q3: checkbox
        let q3 = questions[2]
        #expect(q3.content.type == .checkbox)
        #expect(q3.content.options == ["1", "2", "3", "4", "5"])

        // Q4: external survey
        let q4 = questions[3]
        #expect(q4.content.type == .externalSurvey)
        #expect(q4.content.url == "http://127.0.0.1:3000")
        #expect(q4.content.surveyProvider == "google_forms")
    }

    func test_firstSurvey_getQuestions_filtersCorrectly() async throws {
        let response = try await loadSurveys()
        let survey = response.surveys.first!

        let filtered = survey.getQuestions()

        #expect(filtered.count == 5)
        #expect(filtered.map(\.content.type) == [
            .text, .radio, .checkbox, .externalSurvey, .label
        ])
    }

    // MARK: - Survey Hero Question Submission

    func test_submitSurvey_first_question() async throws {
        setupMockSubmissionSuccess()

        let submissionModel = makeFirstQuestionSubmissionModel()

        let response = try await testRESTService.submitSurveyResponse(submissionModel)

        #expect(response.id == "808d3a515daa39f4c15a")
        #expect(response.updatePath == "/api/v1/survey_responses/808d3a515daa39f4c15a")
        #expect(response.userIdentifier == "b94e83ae-5337-42f4-bec7-2736e7929dcb")
    }

    private func setupMockSubmissionSuccess(_ surveyId: String = "") {
        let data = Fixtures.loadData(file: "survey_submission_response.json")
        mockDataLoader.mock(
            URLString: "https://onebusaway.co/api/v1/survey_responses/\(surveyId)",
            with: data
        )
    }

    private func makeFirstQuestionSubmissionModel() -> SurveySubmission {
        SurveySubmission(
            userIdentifier: uuid,
            surveyId: 1,
            responses: [
                .init(
                    questionId: 15,
                    questionType: "text",
                    questionLabel: "Do you like OBA IOS App ?",
                    answer: "yes"
                )
            ]
        )
    }

    // MARK: - Submit Additional Questions

    func test_submitSurvey_additional_questions() async throws {
        setupMockSubmissionSuccess("surveyResponseId")

        let additionalResponses: [QuestionAnswerSubmission] = [
            .init(questionId: 15, questionType: "text", questionLabel: "Do you like OBA IOS App ?", answer: "yes"),
            .init(questionId: 16, questionType: "radio", questionLabel: "Do you ?", answer: "Yes"),
            .init(questionId: 17, questionType: "checkbox", questionLabel: "Choose", answer: ["1", "3"].joined(separator: ","))
        ]

        let response = try await testRESTService.updateSurveyResponse(
            responseID: "surveyResponseId",
            additionalResponses: additionalResponses
        )

        #expect(response.id == "808d3a515daa39f4c15a")
        #expect(response.updatePath == "/api/v1/survey_responses/808d3a515daa39f4c15a")
        #expect(response.userIdentifier == "b94e83ae-5337-42f4-bec7-2736e7929dcb")
    }

    // MARK: - Error Scenarios

    func test_get_surveys_captive_portal() async throws {
        let data = Fixtures.loadData(file: "captive_portal.html")
        let url = URL(string: "https://onebusaway.co/api/v1/regions/1/surveys.json?user_id=12345-12345-12345-12345-12345")!
        let error = NSError(domain: NSCocoaErrorDomain, code: 3840, userInfo: nil)

        makeResponseFailureMock(data, url: url, statusCode: 200, error: error)

        let thrown = await #expect(throws: APIError.self) {
            try await self.testRESTService.getSurveys(userID: self.uuid)
        }
        guard case .captivePortal = thrown else {
            return XCTFail("Expected APIError.captivePortal, got \(String(describing: thrown))")
        }
    }

    func test_get_surveys_malformed_response_data() async throws {
        let malformedJsonResponse = Fixtures.loadData(file: "surveys_malformed_response.json")
        let url = URL(string: "https://onebusaway.co/api/v1/regions/1/surveys.json?user_id=12345-12345-12345-12345-12345")!

        makeResponseFailureMock(malformedJsonResponse, url: url, statusCode: 200)

        let thrown = await #expect(throws: DecodingError.self) {
            try await self.testRESTService.getSurveys(userID: self.uuid)
        }
        if case let .dataCorrupted(context) = thrown {
            let underlying = context.underlyingError as NSError?
            #expect(underlying?.domain == NSCocoaErrorDomain)
            #expect(underlying?.code == 3840)
        } else {
            Issue.record("Expected DecodingError.dataCorrupted but got \(String(describing: thrown))")
        }
    }

    func test_get_surveys_internal_server_error() async throws {
        let response = Data()
        let url = URL(string: "https://onebusaway.co/api/v1/regions/1/surveys.json?user_id=12345-12345-12345-12345-12345")!

        makeResponseFailureMock(response, url: url, statusCode: 500)

        let thrown = await #expect(throws: APIError.self) {
            try await self.testRESTService.getSurveys(userID: self.uuid)
        }
        guard case .requestFailure(let response) = thrown, response.statusCode == 500 else {
            Issue.record("Expected APIError.requestFailure with 500 as status code but got \(String(describing: thrown))")
            return
        }
    }

    func test_get_surveys_not_found_error() async throws {
        let response = Data()
        let url = URL(string: "https://onebusaway.co/api/v1/regions/1/surveys.json?user_id=12345-12345-12345-12345-12345")!

        makeResponseFailureMock(response, url: url, statusCode: 404)

        let thrown = await #expect(throws: APIError.self) {
            try await self.testRESTService.getSurveys(userID: self.uuid)
        }
        guard case .requestNotFound(let response) = thrown, response.statusCode == 404 else {
            Issue.record("Expected APIError.requestNotFound with 404 as status code but got \(String(describing: thrown))")
            return
        }
    }

    // MARK: - Submit First Question Failures

    func test_submit_first_question_malformed_response_data() async throws {
        let response = Fixtures.loadData(file: "survey_submission_malformed_response.json")
        let url = URL(string: "https://onebusaway.co/api/v1/survey_responses/")!

        makeResponseFailureMock(response, url: url, statusCode: 200)

        let thrown = await #expect(throws: DecodingError.self) {
            let submissionModel = self.makeFirstQuestionSubmissionModel()
            _ = try await self.testRESTService.submitSurveyResponse(submissionModel)
        }
        if case let .dataCorrupted(context) = thrown {
            let underlying = context.underlyingError as NSError?
            #expect(underlying?.domain == NSCocoaErrorDomain)
            #expect(underlying?.code == 3840)
        } else {
            Issue.record("Expected DecodingError.dataCorrupted but got \(String(describing: thrown))")
        }
    }

    func test_submit_first_question_captive_portal() async throws {
        let data = Fixtures.loadData(file: "captive_portal.html")
        let url = URL(string: "https://onebusaway.co/api/v1/survey_responses/")!
        let error = NSError(domain: NSCocoaErrorDomain, code: 3840, userInfo: nil)

        makeResponseFailureMock(data, url: url, statusCode: 200, error: error)

        let thrown = await #expect(throws: APIError.self) {
            let submissionModel = self.makeFirstQuestionSubmissionModel()
            _ = try await self.testRESTService.submitSurveyResponse(submissionModel)
        }
        guard case .captivePortal = thrown else {
            Issue.record("Expected captive portal response to throw APIError.CaptivePortal. Actual value: \(String(describing: thrown))")
            return
        }
    }

    func test_submit_first_question_internal_server_error() async throws {
        let response = Data()
        let url = URL(string: "https://onebusaway.co/api/v1/survey_responses/")!

        makeResponseFailureMock(response, url: url, statusCode: 500)

        let thrown = await #expect(throws: APIError.self) {
            let submissionModel = self.makeFirstQuestionSubmissionModel()
            _ = try await self.testRESTService.submitSurveyResponse(submissionModel)
        }
        guard case .requestFailure(let response) = thrown, response.statusCode == 500 else {
            Issue.record("Expected APIError.requestFailure with 500 as status code but got \(String(describing: thrown))")
            return
        }
    }

    func test_submit_first_question_not_found_error() async throws {
        let response = Data()
        let url = URL(string: "https://onebusaway.co/api/v1/survey_responses/")!

        makeResponseFailureMock(response, url: url, statusCode: 404)

        let thrown = await #expect(throws: APIError.self) {
            let submissionModel = self.makeFirstQuestionSubmissionModel()
            _ = try await self.testRESTService.submitSurveyResponse(submissionModel)
        }
        guard case .requestNotFound(let response) = thrown, response.statusCode == 404 else {
            Issue.record("Expected APIError.requestNotFound with 404 as status code but got \(String(describing: thrown))")
            return
        }
    }

    // MARK: - Submit Additional Question Failures

    func test_submit_additional_question_malformed_response_data() async throws {
        let response = Fixtures.loadData(file: "survey_submission_malformed_response.json")
        let url = URL(string: "https://onebusaway.co/api/v1/survey_responses/surveyResponseId")!

        makeResponseFailureMock(response, url: url, statusCode: 200)

        let thrown = await #expect(throws: DecodingError.self) {
            try await self.testRESTService.updateSurveyResponse(
                responseID: "surveyResponseId",
                additionalResponses: []
            )
        }
        if case let .dataCorrupted(context) = thrown {
            let underlying = context.underlyingError as NSError?
            #expect(underlying?.domain == NSCocoaErrorDomain)
            #expect(underlying?.code == 3840)
        } else {
            Issue.record("Expected DecodingError.dataCorrupted but got \(String(describing: thrown))")
        }
    }

    func test_submit_additional_question_captive_portal() async throws {
        let data = Fixtures.loadData(file: "captive_portal.html")
        let url = URL(string: "https://onebusaway.co/api/v1/survey_responses/surveyResponseId")!
        let error = NSError(domain: NSCocoaErrorDomain, code: 3840, userInfo: nil)

        makeResponseFailureMock(data, url: url, statusCode: 200, error: error)

        let thrown = await #expect(throws: APIError.self) {
            try await self.testRESTService.updateSurveyResponse(
                responseID: "surveyResponseId",
                additionalResponses: []
            )
        }
        guard case .captivePortal = thrown else {
            Issue.record("Expected captive portal response to throw APIError.CaptivePortal. Actual value: \(String(describing: thrown))")
            return
        }
    }

    func test_submit_additional_question_internal_server_error() async throws {
        let response = Data()
        let url = URL(string: "https://onebusaway.co/api/v1/survey_responses/surveyResponseId")!

        makeResponseFailureMock(response, url: url, statusCode: 500)

        let thrown = await #expect(throws: APIError.self) {
            try await self.testRESTService.updateSurveyResponse(
                responseID: "surveyResponseId",
                additionalResponses: []
            )
        }
        guard case .requestFailure(let response) = thrown, response.statusCode == 500 else {
            Issue.record("Expected APIError.requestFailure with 500 as status code but got \(String(describing: thrown))")
            return
        }
    }

    func test_submit_additional_question_not_found_error() async throws {
        let response = Data()
        let url = URL(string: "https://onebusaway.co/api/v1/survey_responses/surveyResponseId")!

        makeResponseFailureMock(response, url: url, statusCode: 404)

        let thrown = await #expect(throws: APIError.self) {
            try await self.testRESTService.updateSurveyResponse(
                responseID: "surveyResponseId",
                additionalResponses: []
            )
        }
        guard case .requestNotFound(let response) = thrown, response.statusCode == 404 else {
            Issue.record("Expected APIError.requestNotFound with 404 as status code but got \(String(describing: thrown))")
            return
        }
    }

    // MARK: - isActive

    func test_isActive_withinDateRange_returnsTrue() {
        let survey = makeSurveyForIsActive(
            startDate: Date().addingTimeInterval(-3600),
            endDate: Date().addingTimeInterval(3600)
        )
        #expect(survey.isActive)
    }

    func test_isActive_pastEndDate_returnsFalse() {
        let survey = makeSurveyForIsActive(
            startDate: Date().addingTimeInterval(-7200),
            endDate: Date().addingTimeInterval(-3600)
        )
        #expect(!survey.isActive)
    }

    func test_isActive_futureStartDate_returnsFalse() {
        let survey = makeSurveyForIsActive(
            startDate: Date().addingTimeInterval(3600),
            endDate: Date().addingTimeInterval(7200)
        )
        #expect(!survey.isActive)
    }

    func test_isActive_nilDates_returnsTrue() {
        let survey = makeSurveyForIsActive(startDate: nil, endDate: nil)
        #expect(survey.isActive)
    }

    private func makeSurveyForIsActive(startDate: Date?, endDate: Date?) -> Survey {
        Survey(
            id: 1, name: "Test", createdAt: Date(), updatedAt: Date(),
            showOnMap: true, showOnStops: true,
            startDate: startDate, endDate: endDate,
            visibleStopsList: nil, visibleRoutesList: nil,
            allowsMultipleResponses: false, alwaysVisible: false,
            study: Study(id: 1, name: "S", description: nil),
            questions: []
        )
    }

    // MARK: - Issue 8: SurveySubmission encodes responses as JSON string

    func test_surveySubmission_encodesResponsesToJSONString() throws {
        let submission = SurveySubmission(
            userIdentifier: "user-1",
            surveyId: 42,
            responses: [
                QuestionAnswerSubmission(
                    questionId: 1,
                    questionType: "text",
                    questionLabel: "Q1",
                    answer: "yes"
                )
            ]
        )

        let encoded = try JSONEncoder().encode(submission)
        let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]

        // responses should be a String (JSON-stringified), not an Array
        let responsesValue = json["responses"]
        #expect(responsesValue is String)

        // The string should be valid JSON containing our response
        let responsesString = responsesValue as! String
        let parsed = try JSONSerialization.jsonObject(with: responsesString.data(using: .utf8)!) as! [[String: Any]]
        #expect(parsed.count == 1)
        #expect((parsed[0]["answer"] as? String) == "yes")
    }

    // MARK: - Missing Optional Fields

    func test_getSurveys_missingOptionalBooleans_defaultsToFalse() async throws {
        let data = Fixtures.loadData(file: "surveys_missing_optional_fields.json")

        mockDataLoader.mock(
            URLString: "https://onebusaway.co/api/v1/regions/1/surveys.json?user_id=12345-12345-12345-12345-12345",
            with: data
        )

        let response = try await testRESTService.getSurveys(userID: uuid)
        let survey = response.surveys.first!

        #expect(!survey.allowsMultipleResponses)
        #expect(!survey.alwaysVisible)
    }

    // MARK: - getSurveys nil region

    func test_getSurveys_nilRegionIdentifier_throwsNoRegionSelected() async {
        let config = APIServiceConfiguration(
            baseURL: baseURL,
            apiKey: apiKey,
            uuid: uuid,
            appVersion: appVersion,
            regionIdentifier: nil,
            surveyBaseURL: surveyBaseURL
        )
        let service = RESTAPIService(config, dataLoader: mockDataLoader)

        let thrown = await #expect(throws: APIError.self) {
            try await service.getSurveys(userID: self.uuid)
        }
        guard case .noRegionSelected = thrown else {
            Issue.record("Expected APIError.noRegionSelected but got \(String(describing: thrown))")
            return
        }
    }

    // MARK: - remainingQuestions

    func test_remainingQuestions_doesNotDropQuestionsWithSamePositionAsHero() {
        let q1 = SurveyQuestion(id: 10, position: 1, required: true, content: QuestionContent(labelText: "Hero", type: .text))
        let q2 = SurveyQuestion(id: 20, position: 1, required: false, content: QuestionContent(labelText: "Also position 1", type: .label))
        let q3 = SurveyQuestion(id: 30, position: 2, required: false, content: QuestionContent(labelText: "Position 2", type: .radio, options: ["A", "B"]))

        let survey = Survey(
            id: 99, name: "Test", createdAt: Date(), updatedAt: Date(),
            showOnMap: true, showOnStops: true, startDate: nil, endDate: nil,
            visibleStopsList: nil, visibleRoutesList: nil,
            allowsMultipleResponses: false, alwaysVisible: false,
            study: Study(id: 1, name: "S", description: nil),
            questions: [q1, q2, q3]
        )

        #expect(survey.heroQuestion?.id == 10)
        #expect(survey.remainingQuestions.count == 2)
        #expect(survey.remainingQuestions.map(\.id) == [20, 30])
    }

    // MARK: - heroQuestionTitle

    func test_heroQuestionTitle_returnsTrimmedHeroText() {
        let survey = makeSurveyWithHero(labelText: "  Help us improve transit  ")
        #expect(survey.heroQuestionTitle == "Help us improve transit")
    }

    func test_heroQuestionTitle_nilWhenHeroTextIsEmpty() {
        let survey = makeSurveyWithHero(labelText: "")
        #expect(survey.heroQuestionTitle == nil)
    }

    func test_heroQuestionTitle_nilWhenHeroTextIsWhitespaceOnly() {
        let survey = makeSurveyWithHero(labelText: "   \n\t ")
        #expect(survey.heroQuestionTitle == nil)
    }

    func test_heroQuestionTitle_nilWhenNoHeroQuestion() {
        // Only a non-hero (position != 1) question exists.
        let survey = makeSurveyWithHero(labelText: "Question", position: 2)
        #expect(survey.heroQuestionTitle == nil)
    }

    private func makeSurveyWithHero(labelText: String, position: Int = 1) -> Survey {
        Survey(
            id: 1, name: "Test", createdAt: Date(), updatedAt: Date(),
            showOnMap: true, showOnStops: true, startDate: nil, endDate: nil,
            visibleStopsList: nil, visibleRoutesList: nil,
            allowsMultipleResponses: false, alwaysVisible: false,
            study: Study(id: 1, name: "S", description: nil),
            questions: [
                SurveyQuestion(id: 1, position: position, required: false,
                               content: QuestionContent(labelText: labelText, type: .text))
            ]
        )
    }

    private func makeResponseFailureMock(_ data: Data, url: URL, statusCode: Int, error: Error? = nil) {
        let urlResponse = mockDataLoader.buildURLResponse(URL: url, statusCode: statusCode)
        let response = MockDataResponse(data: data, urlResponse: urlResponse, error: error) { request in
            let requestURL = request.url!
            return requestURL.host == url.host && requestURL.path == url.path
        }
        mockDataLoader.mock(response: response)
    }

    // MARK: - SurveyService.fetchSurveys()

    @MainActor
    func test_fetchSurveys_nilApiService_setsError() async {
        let store = UserDefaultsStore(userDefaults: userDefaults)
        let service = SurveyService(apiService: nil, userDataStore: store)

        await service.fetchSurveys()

        #expect(service.allSurveys.isEmpty)
        #expect(service.visibleSurveys.isEmpty)
        #expect(service.lastError != nil)

        if case APIError.surveyServiceNotConfigured = service.lastError! {
            // Expected
        } else {
            Issue.record("Expected APIError.surveyServiceNotConfigured but got \(service.lastError!)")
        }
    }

    @MainActor
    func test_fetchSurveys_success_populatesSurveys() async {
        let store = UserDefaultsStore(userDefaults: userDefaults)
        let data = Fixtures.loadData(file: "surveys_always_visible_one_time.json")
        let userID = store.surveyUserIdentifier

        mockDataLoader.mock(
            URLString: "https://onebusaway.co/api/v1/regions/1/surveys.json?user_id=\(userID)",
            with: data
        )

        let service = SurveyService(apiService: testRESTService, userDataStore: store)
        await service.fetchSurveys()

        #expect(service.lastError == nil)
        #expect(service.allSurveys.count == 5)
        #expect(service.visibleSurveys.count == 5)
        #expect(!service.isLoading)
    }

    @MainActor
    func test_fetchSurveys_failure_clearsWhenEmpty() async {
        let store = UserDefaultsStore(userDefaults: userDefaults)
        let userID = store.surveyUserIdentifier

        let url = URL(string: "https://onebusaway.co/api/v1/regions/1/surveys.json?user_id=\(userID)")!
        makeResponseFailureMock(Data(), url: url, statusCode: 500)

        let service = SurveyService(apiService: testRESTService, userDataStore: store)
        await service.fetchSurveys()

        #expect(service.allSurveys.isEmpty)
        #expect(service.visibleSurveys.isEmpty)
        #expect(service.lastError != nil)
        #expect(!service.isLoading)
    }

    // MARK: - Staleness / Cooldown Tests

    @MainActor
    func test_fetchSurveys_cooldownSkipsSecondFetch() async {
        let store = UserDefaultsStore(userDefaults: userDefaults)
        let userID = store.surveyUserIdentifier

        let successData = Fixtures.loadData(file: "surveys_always_visible_one_time.json")
        mockDataLoader.mock(
            URLString: "https://onebusaway.co/api/v1/regions/1/surveys.json?user_id=\(userID)",
            with: successData
        )

        let service = SurveyService(apiService: testRESTService, userDataStore: store)
        await service.fetchSurveys()

        let initialCount = service.allSurveys.count
        #expect(initialCount > 0)

        // Replace mock with different data — but cooldown should prevent fetching
        mockDataLoader.removeMappedResponses()
        let url = URL(string: "https://onebusaway.co/api/v1/regions/1/surveys.json?user_id=\(userID)")!
        makeResponseFailureMock(Data(), url: url, statusCode: 500)

        await service.fetchSurveys()

        // Should still have original surveys (cooldown prevented re-fetch)
        #expect(service.allSurveys.count == initialCount)
        #expect(service.lastError == nil)  // no error because fetch was skipped
    }

    @MainActor
    func test_fetchSurveys_forceBypassesCooldown() async {
        let store = UserDefaultsStore(userDefaults: userDefaults)
        let userID = store.surveyUserIdentifier

        let successData = Fixtures.loadData(file: "surveys_always_visible_one_time.json")
        mockDataLoader.mock(
            URLString: "https://onebusaway.co/api/v1/regions/1/surveys.json?user_id=\(userID)",
            with: successData
        )

        let service = SurveyService(apiService: testRESTService, userDataStore: store)
        await service.fetchSurveys()

        let initialCount = service.allSurveys.count
        #expect(initialCount > 0)

        // force: true should bypass cooldown and actually fetch
        await service.fetchSurveys(force: true)

        // Fetch went through (no error since same mock data is still valid)
        #expect(service.allSurveys.count == initialCount)
        #expect(service.lastError == nil)
    }

    @MainActor
    func test_fetchSurveys_emptySurveysBypassesCooldown() async {
        let store = UserDefaultsStore(userDefaults: userDefaults)
        let userID = store.surveyUserIdentifier

        // First fetch fails, leaving allSurveys empty
        let url = URL(string: "https://onebusaway.co/api/v1/regions/1/surveys.json?user_id=\(userID)")!
        makeResponseFailureMock(Data(), url: url, statusCode: 500)

        let service = SurveyService(apiService: testRESTService, userDataStore: store)
        await service.fetchSurveys()

        #expect(service.allSurveys.isEmpty)
        #expect(service.lastError != nil)

        // Replace with success data — should fetch because allSurveys is empty
        mockDataLoader.removeMappedResponses()
        let successData = Fixtures.loadData(file: "surveys_always_visible_one_time.json")
        mockDataLoader.mock(
            URLString: "https://onebusaway.co/api/v1/regions/1/surveys.json?user_id=\(userID)",
            with: successData
        )

        await service.fetchSurveys()

        // Should have fetched despite cooldown because allSurveys was empty
        #expect(service.allSurveys.count > 0)
        #expect(service.lastError == nil)
    }

    @MainActor
    func test_fetchSurveys_failure_preservesExistingSurveys() async {
        let store = UserDefaultsStore(userDefaults: userDefaults)
        let userID = store.surveyUserIdentifier

        // First, load surveys successfully
        let successData = Fixtures.loadData(file: "surveys_always_visible_one_time.json")
        mockDataLoader.mock(
            URLString: "https://onebusaway.co/api/v1/regions/1/surveys.json?user_id=\(userID)",
            with: successData
        )

        let service = SurveyService(apiService: testRESTService, userDataStore: store)
        await service.fetchSurveys()

        let initialCount = service.allSurveys.count
        #expect(initialCount > 0)

        // Now simulate a failure on second fetch
        mockDataLoader.removeMappedResponses()
        let url = URL(string: "https://onebusaway.co/api/v1/regions/1/surveys.json?user_id=\(userID)")!
        makeResponseFailureMock(Data(), url: url, statusCode: 500)

        await service.fetchSurveys(force: true)

        // Surveys should be preserved, not cleared
        #expect(service.allSurveys.count == initialCount)
        #expect(service.lastError != nil)
    }

}
