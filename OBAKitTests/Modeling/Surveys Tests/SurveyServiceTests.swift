//
//  SurveyServiceTests.swift
//  OBAKitTests
//
//  Created by Mohamed Sliem on 04/12/2025.
//

import XCTest
import Nimble
@testable import OBAKitCore

final class SurveyServiceTests: OBATestCase {

    // MARK: - Helpers

    private var mockDataLoader: MockDataLoader!
    private var testRESTService: RESTAPIService!

    override func setUp() {
        super.setUp()
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

    private func loadSurveys() async throws -> RESTAPIResponse<StudyResponse> {
        let data = Fixtures.loadData(file: "rest_surveys_always_visible_one_time.json")

        mockDataLoader.mock(
            URLString: "https://onebusaway.co/api/v1/regions/1/surveys.json?user_id=12345-12345-12345-12345-12345",
            with: data
        )
        return try await testRESTService.getSurveys(userID: uuid)
    }

    func test_getSurveys_success_metadata() async throws {
        let response = try await loadSurveys()
        let surveys = response.entry

        expect(surveys.region.name).to(equal("Puget Sound"))
        expect(surveys.region.id).to(equal(1))

        expect(surveys.surveys.count).to(equal(5))
        expect(surveys).toNot(beNil())
    }

    func test_firstSurvey_basicProperties() async throws {
        let response = try await loadSurveys()
        let survey = response.entry.surveys.first

        expect(survey).toNot(beNil())

        expect(survey?.id).to(equal(1))
        expect(survey?.name).to(equal("Always Visible — One-Time"))
        expect(survey?.showOnMap).to(beTrue())
        expect(survey?.showOnStops).to(beTrue())
        expect(survey?.alwaysVisible).to(beTrue())
        expect(survey?.allowsMultipleResponses).to(beFalse())

        expect(survey?.visibleStopsList?.count).to(equal(2))
        expect(survey?.visibleRoutesList?.count).to(equal(2))
        expect(survey?.questions.count).to(equal(5))
    }

    func test_firstSurvey_questionDecoding() async throws {
        let response = try await loadSurveys()
        let survey = response.entry.surveys.first!

        let questions = survey.questions
        expect(questions.count).to(equal(5))

        // Q1: text
        let q1 = questions[0]
        expect(q1.content.type).to(equal(.text))
        expect(q1.content.labelText).to(equal("Do you like OBA IOS App ?"))

        // Q2: radio
        let q2 = questions[1]
        expect(q2.content.type).to(equal(.radio))
        expect(q2.content.options).to(equal(["Yes", "No"]))

        // Q3: checkbox
        let q3 = questions[2]
        expect(q3.content.type).to(equal(.checkbox))
        expect(q3.content.options).to(equal(["1", "2", "3", "4", "5"]))

        // Q4: external survey
        let q4 = questions[3]
        expect(q4.content.type).to(equal(.externalSurvey))
        expect(q4.content.url).to(equal("http://127.0.0.1:3000"))
        expect(q4.content.surveyProvider).to(equal("google_forms"))
    }

    func test_firstSurvey_getQuestions_filtersCorrectly() async throws {
        let response = try await loadSurveys()
        let survey = response.entry.surveys.first!

        let filtered = survey.getQuestions()

        expect(filtered.count).to(equal(5))
        expect(filtered.map(\.content.type)).to(equal([
            .text, .radio, .checkbox, .externalSurvey, .label
        ]))
    }

    // MARK: - Survey Hero Question Submission

    func test_submitSurvey_first_question() async throws {
        setupMockSubmissionSuccess()

        let submissionModel = makeFirstQuestionSubmissionModel()

        let response = try await testRESTService.submitSurveyResponse(submissionModel)
        let submissionResponse = response.entry

        expect(submissionResponse.id).to(equal("808d3a515daa39f4c15a"))
        expect(submissionResponse.updatePath).to(equal("/api/v1/survey_responses/808d3a515daa39f4c15a"))
        expect(submissionResponse.userIdentifier).to(equal("b94e83ae-5337-42f4-bec7-2736e7929dcb"))
    }

    private func setupMockSubmissionSuccess(_ surveyId: String = "") {
        let data = Fixtures.loadData(file: "rest_survey_submission_response.json")
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
        let submissionResponse = response.entry

        expect(submissionResponse.id).to(equal("808d3a515daa39f4c15a"))
        expect(submissionResponse.updatePath).to(equal("/api/v1/survey_responses/808d3a515daa39f4c15a"))
        expect(submissionResponse.userIdentifier).to(equal("b94e83ae-5337-42f4-bec7-2736e7929dcb"))
    }

    // MARK: - Error Scenarios

    func test_get_surveys_captive_portal() async throws {
        let data = Fixtures.loadData(file: "captive_portal.html")
        let url = URL(string: "https://onebusaway.co/api/v1/regions/1/surveys.json?user_id=12345-12345-12345-12345-12345")!
        let error = NSError(domain: NSCocoaErrorDomain, code: 3840, userInfo: nil)

        makeResponseFailureMock(data, url: url, statusCode: 200, error: error)

        await expect {
            try await self.testRESTService.getSurveys(userID: self.uuid)
        }
        .to(throwError { error in
            if case APIError.captivePortal = error {
                return
            }
            fail("Expected captive portal response to throw APIError.CaptivePortal. Actual value: \(error)")
        })
    }

    func test_get_surveys_malformed_response_data() async throws {
        let malformedJsonResponse = Fixtures.loadData(file: "surveys_malformed_response.json")
        let url = URL(string: "https://onebusaway.co/api/v1/regions/1/surveys.json?user_id=12345-12345-12345-12345-12345")!

        makeResponseFailureMock(malformedJsonResponse, url: url, statusCode: 200)

        await expect {
            try await self.testRESTService.getSurveys(userID: self.uuid)
        }
        .to(throwError { error in
            if case let DecodingError.dataCorrupted(context) = error {
                let underlying = context.underlyingError as NSError?
                expect(underlying?.domain) == NSCocoaErrorDomain
                expect(underlying?.code) == 3840
            } else {
                fail("Expected DecodingError.dataCorrupted but got \(error)")
            }
        })
    }

    func test_get_surveys_internal_server_error() async throws {
        let response = Data()
        let url = URL(string: "https://onebusaway.co/api/v1/regions/1/surveys.json?user_id=12345-12345-12345-12345-12345")!

        makeResponseFailureMock(response, url: url, statusCode: 500)

        await expect {
            try await self.testRESTService.getSurveys(userID: self.uuid)
        }
        .to(throwError { error in
            if case APIError.requestFailure(let response) = error, response.statusCode == 500 {
                return
            }
            fail("Expected APIError.requestFailure with 500 as status code but got \(error)")
        })
    }

    func test_get_surveys_not_found_error() async throws {
        let response = Data()
        let url = URL(string: "https://onebusaway.co/api/v1/regions/1/surveys.json?user_id=12345-12345-12345-12345-12345")!

        makeResponseFailureMock(response, url: url, statusCode: 404)

        await expect {
            try await self.testRESTService.getSurveys(userID: self.uuid)
        }
        .to(throwError { error in
            if case APIError.requestNotFound(let response) = error, response.statusCode == 404 {
                return
            }
            fail("Expected APIError.requestNotFound with 404 as status code but got \(error)")
        })
    }

    // MARK: - Submit First Question Failures

    func test_submit_first_question_malformed_response_data() async throws {
        let response = Fixtures.loadData(file: "survey_submission_malformed_response.json")
        let url = URL(string: "https://onebusaway.co/api/v1/survey_responses/")!

        makeResponseFailureMock(response, url: url, statusCode: 200)

        await expect {
            let submissionModel = self.makeFirstQuestionSubmissionModel()
            _ = try await self.testRESTService.submitSurveyResponse(submissionModel)
        }
        .to(throwError { error in
            if case let DecodingError.dataCorrupted(context) = error {
                let underlying = context.underlyingError as NSError?
                expect(underlying?.domain) == NSCocoaErrorDomain
                expect(underlying?.code) == 3840
            } else {
                fail("Expected DecodingError.dataCorrupted but got \(error)")
            }
        })
    }

    func test_submit_first_question_captive_portal() async throws {
        let data = Fixtures.loadData(file: "captive_portal.html")
        let url = URL(string: "https://onebusaway.co/api/v1/survey_responses/")!
        let error = NSError(domain: NSCocoaErrorDomain, code: 3840, userInfo: nil)

        makeResponseFailureMock(data, url: url, statusCode: 200, error: error)

        await expect {
            let submissionModel = self.makeFirstQuestionSubmissionModel()
            _ = try await self.testRESTService.submitSurveyResponse(submissionModel)
        }
        .to(throwError { error in
            if case APIError.captivePortal = error {
                return
            }
            fail("Expected captive portal response to throw APIError.CaptivePortal. Actual value: \(error)")
        })
    }

    func test_submit_first_question_internal_server_error() async throws {
        let response = Data()
        let url = URL(string: "https://onebusaway.co/api/v1/survey_responses/")!

        makeResponseFailureMock(response, url: url, statusCode: 500)

        await expect {
            let submissionModel = self.makeFirstQuestionSubmissionModel()
            _ = try await self.testRESTService.submitSurveyResponse(submissionModel)
        }
        .to(throwError { error in
            if case APIError.requestFailure(let response) = error, response.statusCode == 500 {
                return
            }
            fail("Expected APIError.requestFailure with 500 as status code but got \(error)")
        })
    }

    func test_submit_first_question_not_found_error() async throws {
        let response = Data()
        let url = URL(string: "https://onebusaway.co/api/v1/survey_responses/")!

        makeResponseFailureMock(response, url: url, statusCode: 404)

        await expect {
            let submissionModel = self.makeFirstQuestionSubmissionModel()
            _ = try await self.testRESTService.submitSurveyResponse(submissionModel)
        }
        .to(throwError { error in
            if case APIError.requestNotFound(let response) = error, response.statusCode == 404 {
                return
            }
            fail("Expected APIError.requestNotFound with 404 as status code but got \(error)")
        })
    }

    // MARK: - Submit Additional Question Failures

    func test_submit_additional_question_malformed_response_data() async throws {
        let response = Fixtures.loadData(file: "survey_submission_malformed_response.json")
        let url = URL(string: "https://onebusaway.co/api/v1/survey_responses/surveyResponseId")!

        makeResponseFailureMock(response, url: url, statusCode: 200)

        await expect {
            try await self.testRESTService.updateSurveyResponse(
                responseID: "surveyResponseId",
                additionalResponses: []
            )
        }
        .to(throwError { error in
            if case let DecodingError.dataCorrupted(context) = error {
                let underlying = context.underlyingError as NSError?
                expect(underlying?.domain) == NSCocoaErrorDomain
                expect(underlying?.code) == 3840
            } else {
                fail("Expected DecodingError.dataCorrupted but got \(error)")
            }
        })
    }

    func test_submit_additional_question_captive_portal() async throws {
        let data = Fixtures.loadData(file: "captive_portal.html")
        let url = URL(string: "https://onebusaway.co/api/v1/survey_responses/surveyResponseId")!
        let error = NSError(domain: NSCocoaErrorDomain, code: 3840, userInfo: nil)

        makeResponseFailureMock(data, url: url, statusCode: 200, error: error)

        await expect {
            try await self.testRESTService.updateSurveyResponse(
                responseID: "surveyResponseId",
                additionalResponses: []
            )
        }
        .to(throwError { error in
            if case APIError.captivePortal = error {
                return
            }
            fail("Expected captive portal response to throw APIError.CaptivePortal. Actual value: \(error)")
        })
    }

    func test_submit_additional_question_internal_server_error() async throws {
        let response = Data()
        let url = URL(string: "https://onebusaway.co/api/v1/survey_responses/surveyResponseId")!

        makeResponseFailureMock(response, url: url, statusCode: 500)

        await expect {
            try await self.testRESTService.updateSurveyResponse(
                responseID: "surveyResponseId",
                additionalResponses: []
            )
        }
        .to(throwError { error in
            if case APIError.requestFailure(let response) = error, response.statusCode == 500 {
                return
            }
            fail("Expected APIError.requestFailure with 500 as status code but got \(error)")
        })
    }

    func test_submit_additional_question_not_found_error() async throws {
        let response = Data()
        let url = URL(string: "https://onebusaway.co/api/v1/survey_responses/surveyResponseId")!

        makeResponseFailureMock(response, url: url, statusCode: 404)

        await expect {
            try await self.testRESTService.updateSurveyResponse(
                responseID: "surveyResponseId",
                additionalResponses: []
            )
        }
        .to(throwError { error in
            if case APIError.requestNotFound(let response) = error, response.statusCode == 404 {
                return
            }
            fail("Expected APIError.requestNotFound with 404 as status code but got \(error)")
        })
    }

    // MARK: - isActive

    func test_isActive_withinDateRange_returnsTrue() {
        let survey = makeSurveyForIsActive(
            startDate: Date().addingTimeInterval(-3600),
            endDate: Date().addingTimeInterval(3600)
        )
        expect(survey.isActive).to(beTrue())
    }

    func test_isActive_pastEndDate_returnsFalse() {
        let survey = makeSurveyForIsActive(
            startDate: Date().addingTimeInterval(-7200),
            endDate: Date().addingTimeInterval(-3600)
        )
        expect(survey.isActive).to(beFalse())
    }

    func test_isActive_futureStartDate_returnsFalse() {
        let survey = makeSurveyForIsActive(
            startDate: Date().addingTimeInterval(3600),
            endDate: Date().addingTimeInterval(7200)
        )
        expect(survey.isActive).to(beFalse())
    }

    func test_isActive_nilDates_returnsTrue() {
        let survey = makeSurveyForIsActive(startDate: nil, endDate: nil)
        expect(survey.isActive).to(beTrue())
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

        await expect {
            try await service.getSurveys(userID: self.uuid)
        }.to(throwError { error in
            if case APIError.noRegionSelected = error {
                return
            }
            fail("Expected APIError.noRegionSelected but got \(error)")
        })
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

        expect(survey.heroQuestion?.id).to(equal(10))
        expect(survey.remainingQuestions.count).to(equal(2))
        expect(survey.remainingQuestions.map(\.id)).to(equal([20, 30]))
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

        expect(service.allSurveys).to(beEmpty())
        expect(service.visibleSurveys).to(beEmpty())
        expect(service.lastError).toNot(beNil())

        if case APIError.surveyServiceNotConfigured = service.lastError! {
            // Expected
        } else {
            fail("Expected APIError.surveyServiceNotConfigured but got \(service.lastError!)")
        }
    }

    @MainActor
    func test_fetchSurveys_success_populatesSurveys() async {
        let store = UserDefaultsStore(userDefaults: userDefaults)
        let data = Fixtures.loadData(file: "rest_surveys_always_visible_one_time.json")
        let userID = store.surveyUserIdentifier

        mockDataLoader.mock(
            URLString: "https://onebusaway.co/api/v1/regions/1/surveys.json?user_id=\(userID)",
            with: data
        )

        let service = SurveyService(apiService: testRESTService, userDataStore: store)
        await service.fetchSurveys()

        expect(service.allSurveys.count).to(equal(5))
        expect(service.visibleSurveys.count).to(equal(5))
        expect(service.lastError).to(beNil())
        expect(service.isLoading).to(beFalse())
    }

    @MainActor
    func test_fetchSurveys_failure_clearsWhenEmpty() async {
        let store = UserDefaultsStore(userDefaults: userDefaults)
        let userID = store.surveyUserIdentifier

        let url = URL(string: "https://onebusaway.co/api/v1/regions/1/surveys.json?user_id=\(userID)")!
        makeResponseFailureMock(Data(), url: url, statusCode: 500)

        let service = SurveyService(apiService: testRESTService, userDataStore: store)
        await service.fetchSurveys()

        expect(service.allSurveys).to(beEmpty())
        expect(service.visibleSurveys).to(beEmpty())
        expect(service.lastError).toNot(beNil())
        expect(service.isLoading).to(beFalse())
    }

    @MainActor
    func test_fetchSurveys_failure_preservesExistingSurveys() async {
        let store = UserDefaultsStore(userDefaults: userDefaults)
        let userID = store.surveyUserIdentifier

        // First, load surveys successfully
        let successData = Fixtures.loadData(file: "rest_surveys_always_visible_one_time.json")
        mockDataLoader.mock(
            URLString: "https://onebusaway.co/api/v1/regions/1/surveys.json?user_id=\(userID)",
            with: successData
        )

        let service = SurveyService(apiService: testRESTService, userDataStore: store)
        await service.fetchSurveys()

        let initialCount = service.allSurveys.count
        expect(initialCount).to(beGreaterThan(0))

        // Now simulate a failure on second fetch
        mockDataLoader.removeMappedResponses()
        let url = URL(string: "https://onebusaway.co/api/v1/regions/1/surveys.json?user_id=\(userID)")!
        makeResponseFailureMock(Data(), url: url, statusCode: 500)

        await service.fetchSurveys(force: true)

        // Surveys should be preserved, not cleared
        expect(service.allSurveys.count).to(equal(initialCount))
        expect(service.lastError).toNot(beNil())
    }

}
