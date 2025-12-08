//
//  SurveyServiceTests.swift
//  OBAKitTests
//
//  Created by Mohamed Sliem on 04/12/2025.
//

import OBAKitCore
import XCTest
import Nimble
@testable import OBAKitCore

final class SurveyServiceTests: OBATestCase {

    // MARK: - GET Surveys
    private func loadSurveys() async throws -> StudyResponse {
        let dataLoader = surveyAPIService.dataLoader as! MockDataLoader
        let data = Fixtures.loadData(file: "surveys_always_visible_one_time.json")

        dataLoader.mock(
            URLString: "https://onebusaway.co/api/v1/regions/1/surveys.json?user_id=12345-12345-12345-12345-12345",
            with: data
        )
        return try await surveyAPIService.getSurveys()
    }

    // Test metadata (region + survey list basics)
    func test_getSurveys_success_metadata() async throws {
        let surveys = try await loadSurveys()

        expect(surveys.region.name).to(equal("Puget Sound"))
        expect(surveys.region.id).to(equal(1))

        expect(surveys.surveys.count).to(equal(5))
        expect(surveys).toNot(beNil())
    }

    // Test the FIRST survey basic fields (id, names, flags)
    func test_firstSurvey_basicProperties() async throws {
        let surveys = try await loadSurveys()

        let survey = surveys.surveys.first
        expect(survey).toNot(beNil())

        expect(survey?.id).to(equal(1))
        expect(survey?.name).to(equal("Always Visible — One-Time"))
        expect(survey?.showOnMap).to(beTrue())
        expect(survey?.showOnStops).to(beTrue())
        expect(survey?.allowsVisible).to(beTrue())
        expect(survey?.allowsMultipleResponses).to(beFalse())

        expect(survey?.visibleStopsList?.count).to(equal(2))
        expect(survey?.visibleRoutesList?.count).to(equal(2))
        expect(survey?.questions.count).to(equal(5))
    }

    // Test question decoding and types
    func test_firstSurvey_questionDecoding() async throws {
        let surveys = try await loadSurveys()
        let survey = surveys.surveys.first!

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

    // Test getQuestions() filtering logic
    func test_firstSurvey_getQuestions_filtersCorrectly() async throws {
        let surveys = try await loadSurveys()
        let survey = surveys.surveys.first!

        let filtered = survey.getQuestions()

        expect(filtered.count).to(equal(5)) // all valid
        expect(filtered.map(\.content.type)).to(equal([
            .text, .radio, .checkbox, .externalSurvey, .label
        ]))
    }

    // MARK: - Survey Hero Question Submission
    func test_submitSurvey_first_question() async throws {

        setupMockSubmissionSuccess()

        let submissionModel = makeFirstQuestionSubmissionModel()

        let submissionResponse = try await surveyAPIService.submitSurveyResponse(surveyResponse: submissionModel)

        expect(submissionResponse.id).to(equal("808d3a515daa39f4c15a"))
        expect(submissionResponse.updatePath).to(equal("/api/v1/survey_responses/808d3a515daa39f4c15a"))
        expect(submissionResponse.userIdentifier).to(equal("b94e83ae-5337-42f4-bec7-2736e7929dcb"))

    }


    private func setupMockSubmissionSuccess(_ surveyId: String = "") {
        let dataLoader = surveyAPIService.dataLoader as! MockDataLoader
        let data = Fixtures.loadData(file: "survey_submission_response.json")
        dataLoader.mock(
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

        let submissionModel = makeAdditionalQuestionSubmissionModel()

        let submissionResponse = try await surveyAPIService.updateSurveyResponse(
            surveyResponseId: "surveyResponseId",
            surveyResponses: submissionModel
        )

        expect(submissionResponse.id).to(equal("808d3a515daa39f4c15a"))
        expect(submissionResponse.updatePath).to(equal("/api/v1/survey_responses/808d3a515daa39f4c15a"))
        expect(submissionResponse.userIdentifier).to(equal("b94e83ae-5337-42f4-bec7-2736e7929dcb"))

    }

    private func makeAdditionalQuestionSubmissionModel() -> SurveySubmission {
        SurveySubmission(
            userIdentifier: uuid,
            surveyId: 1,
            responses: [
                // Q1: Text
                .init(
                    questionId: 15,
                    questionType: "text",
                    questionLabel: "Do you like OBA IOS App ?",
                    answer: "yes"
                ),
                // Q2: Radio
                .init(
                    questionId: 16,
                    questionType: "radio",
                    questionLabel: "Do you ?",
                    answer: "Yes"
                ),
                // Q3: Checkbox
                .init(
                    questionId: 17,
                    questionType: "checkbox",
                    questionLabel: "Choose",
                    answer: ["1", "3"].joined(separator: ",")
                )
            ]
        )
    }

    // MARK: - Error Scenarios

    // MARK: - Get Surveys Failures
    func test_get_surveys_captive_portal() async throws {
        let data = Fixtures.loadData(file: "captive_portal.html")
        let url = URL(string: "https://onebusaway.co/api/v1/regions/1/surveys.json?user_id=12345-12345-12345-12345-12345")!
        let error = NSError(domain: NSCocoaErrorDomain, code: 3840, userInfo: nil)

        makeResponseFailureMock(data, url: url, statusCode: 200, error: error)

        await expect {
            try await self.surveyAPIService.getSurveys()
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
            try await self.surveyAPIService.getSurveys()
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
            try await self.surveyAPIService.getSurveys()
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
            try await self.surveyAPIService.getSurveys()
        }
        .to(throwError { error in

            if case APIError.requestNotFound(let response) = error, response.statusCode == 404 {
                return
            }

            fail("Expected APIError.requestNotFound with 404 as status code but got \(error)")
        })
    }

    //MARK: -  Submit First Question Failures
    func test_submit_first_question_malformed_response_data() async throws {
        let response = Fixtures.loadData(file: "survey_submission_malformed_response.json")
        let url = URL(string: "https://onebusaway.co/api/v1/survey_responses/")!

        makeResponseFailureMock(response, url: url, statusCode: 200)

        await expect {
            let submissionModel = self.makeFirstQuestionSubmissionModel()
            let _ = try await self.surveyAPIService.submitSurveyResponse(surveyResponse: submissionModel)
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
            let _ = try await self.surveyAPIService.submitSurveyResponse(surveyResponse: submissionModel)
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
            let _ = try await self.surveyAPIService.submitSurveyResponse(surveyResponse: submissionModel)
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
            let _ = try await self.surveyAPIService.submitSurveyResponse(surveyResponse: submissionModel)
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
            let submissionModel = self.makeAdditionalQuestionSubmissionModel()
            try await self.surveyAPIService.updateSurveyResponse(
                surveyResponseId: "surveyResponseId",
                surveyResponses: submissionModel
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
            let submissionModel = self.makeAdditionalQuestionSubmissionModel()
            try await self.surveyAPIService.updateSurveyResponse(
                surveyResponseId: "surveyResponseId",
                surveyResponses: submissionModel
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
            let submissionModel = self.makeAdditionalQuestionSubmissionModel()
            try await self.surveyAPIService.updateSurveyResponse(
                surveyResponseId: "surveyResponseId",
                surveyResponses: submissionModel
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
            let submissionModel = self.makeAdditionalQuestionSubmissionModel()
            try await self.surveyAPIService.updateSurveyResponse(
                surveyResponseId: "surveyResponseId",
                surveyResponses: submissionModel
            )
        }
        .to(throwError { error in

            if case APIError.requestNotFound(let response) = error, response.statusCode == 404 {
                return
            }

            fail("Expected APIError.requestNotFound with 404 as status code but got \(error)")
        })
    }

    private func makeResponseFailureMock(_ data: Data, url: URL, statusCode: Int, error: Error? = nil) {
        let dataLoader = surveyAPIService.dataLoader as! MockDataLoader
        let urlResponse = dataLoader.buildURLResponse(URL: url, statusCode: statusCode)
        let response = MockDataResponse(data: data, urlResponse: urlResponse, error: error) { request in
            request.url == url
        }
        dataLoader.mock(response: response)
    }

    // MARK: - Missed Region Identifier

    func test_missing_region_identifier() async throws {
        let apiConfig = APIServiceConfiguration(baseURL: URL(string: "https://onebusaway.co/api/v1/")!, uuid: "userIdentifier", regionIdentifier: nil)
        expect {
            SurveyAPIService(apiConfig, dataLoader: MockDataLoader(testName: self.name))
        }
        .to(throwAssertion())
    }

}
