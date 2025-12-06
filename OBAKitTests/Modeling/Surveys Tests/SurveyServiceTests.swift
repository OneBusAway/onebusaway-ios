//
//  SurveyServiceTests.swift
//  OBAKitTests
//
//  Created by Mohamed Sliem on 04/12/2025.
//

import OBAKitCore
import XCTest
import Nimble

final class SurveyServiceTests: OBATestCase {

    // MARK: - GET Surveys
    private func loadSurveys() async throws -> StudyResponse {
        let dataLoader = surveyAPIService.dataLoader as! MockDataLoader
        let data = Fixtures.loadData(file: "surveys_always_visible_one_time.json")
        print(data.count)
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
        expect(survey?.questions.count).to(equal(4))
    }

    // Test question decoding and types
    func test_firstSurvey_questionDecoding() async throws {
        let surveys = try await loadSurveys()
        let survey = surveys.surveys.first!

        let questions = survey.questions
        expect(questions.count).to(equal(4))

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

        expect(filtered.count).to(equal(4)) // all valid
        expect(filtered.map(\.content.type)).to(equal([
            .text, .radio, .checkbox, .externalSurvey
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


    private func setupMockSubmissionSuccess() {
        let dataLoader = surveyAPIService.dataLoader as! MockDataLoader
        let data = Fixtures.loadData(file: "survey_submission_response.json")
        dataLoader.mock(
            URLString: "https://onebusaway.co/api/v1/survey_responses/",
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

        setupMockSubmissionSuccess()

        let submissionModel = makeAdditionalQuestionSubmissionModel()

        let submissionResponse = try await surveyAPIService.submitSurveyResponse(surveyResponse: submissionModel)

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
    
}
