//
//  SurveyModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class SurveyModelTests: OBATestCase {

    // MARK: - StudyResponse Decoding & Equality

    @Test func `StudyResponse decodes complete payload`() throws {
        let data = Fixtures.loadData(file: "surveys_always_visible_one_time.json")
        let response = try JSONDecoder.obacoServiceDecoder.decode(StudyResponse.self, from: data)

        #expect(response.region.id == 1)
        #expect(response.region.name == "Puget Sound")
        #expect(response.surveys.count == 5)

        let first = try #require(response.surveys.first)
        #expect(first.id == 1)
        #expect(first.name == "Always Visible — One-Time")
        #expect(first.study.id == 1)
        #expect(first.study.name == "OBA 2025")
    }

    @Test func `StudyResponse equality and hashing`() throws {
        let data = Fixtures.loadData(file: "surveys_always_visible_one_time.json")
        let resp1 = try JSONDecoder.obacoServiceDecoder.decode(StudyResponse.self, from: data)
        let resp2 = try JSONDecoder.obacoServiceDecoder.decode(StudyResponse.self, from: data)

        #expect(resp1 == resp2)
        #expect(resp1.hashValue == resp2.hashValue)
        #expect(resp1.region == resp2.region)
        #expect(resp1.region.hashValue == resp2.region.hashValue)
    }

    // MARK: - Survey Questions Filtering

    @Test func `getQuestions filters out invalid question content`() {
        let validText = SurveysTestHelpers.makeSurveyQuestion(
            id: 1,
            position: 1,
            type: .text,
            labelText: "What do you think?"
        )
        let validRadio = SurveysTestHelpers.makeSurveyQuestion(
            id: 2,
            position: 2,
            type: .radio,
            labelText: "Pick one",
            options: ["Option A", "Option B"]
        )
        let validCheckbox = SurveysTestHelpers.makeSurveyQuestion(
            id: 3,
            position: 3,
            type: .checkbox,
            labelText: "Pick any",
            options: ["Option 1", "Option 2"]
        )
        let validLabel = SurveysTestHelpers.makeSurveyQuestion(
            id: 4,
            position: 4,
            type: .label,
            labelText: "Informational note"
        )
        let validExternal = SurveysTestHelpers.makeSurveyQuestion(
            id: 5,
            position: 5,
            type: .externalSurvey,
            labelText: "External",
            url: "https://example.com/survey"
        )

        let survey = SurveysTestHelpers.makeSurvey(
            questions: [validText, validRadio, validCheckbox, validLabel, validExternal]
        )

        let filtered = survey.getQuestions()
        #expect(filtered.count == 5)
        #expect(filtered.map(\.id) == [1, 2, 3, 4, 5])
    }

    // MARK: - Survey Question Content Helpers & Compatibility

    @Test func `QuestionContent displayText and typeString match values`() {
        let content = SurveysTestHelpers.makeQuestionContent(
            type: .radio,
            labelText: "Preferred Mode?",
            options: ["Bus", "Train"]
        )

        #expect(content.displayText == "Preferred Mode?")
        #expect(content.typeString == "radio")
    }

    // MARK: - Survey Hero & Remaining Questions

    @Test func `Hero question returns position 1 question`() {
        let q1 = SurveysTestHelpers.makeSurveyQuestion(id: 10, position: 2, labelText: "Q2")
        let q2 = SurveysTestHelpers.makeSurveyQuestion(id: 20, position: 1, labelText: "Q1 Hero")
        let q3 = SurveysTestHelpers.makeSurveyQuestion(id: 30, position: 3, labelText: "Q3")

        let survey = SurveysTestHelpers.makeSurvey(questions: [q1, q2, q3])
        #expect(survey.heroQuestion?.id == 20)
        #expect(survey.heroQuestionTitle == "Q1 Hero")
        #expect(survey.remainingQuestions.map(\.id) == [10, 30])
    }

    @Test func `Remaining questions returns all questions when hero question is absent`() {
        let q1 = SurveysTestHelpers.makeSurveyQuestion(id: 10, position: 2, labelText: "Q2")
        let q2 = SurveysTestHelpers.makeSurveyQuestion(id: 30, position: 3, labelText: "Q3")

        let survey = SurveysTestHelpers.makeSurvey(questions: [q1, q2])
        #expect(survey.heroQuestion == nil)
        #expect(survey.heroQuestionTitle == nil)
        #expect(survey.remainingQuestions.map(\.id) == [10, 30])
    }

    // MARK: - Survey Visibility: Map

    @Test func `shouldShowOnMap requires both showOnMap and isActive`() {
        let calendar = Calendar.current
        let past = calendar.date(byAdding: .day, value: -2, to: Date())!
        let future = calendar.date(byAdding: .day, value: 2, to: Date())!

        let activeOnMap = SurveysTestHelpers.makeSurvey(
            showOnMap: true,
            startDate: past,
            endDate: future
        )
        #expect(activeOnMap.shouldShowOnMap)

        let inactiveOnMap = SurveysTestHelpers.makeSurvey(
            showOnMap: true,
            startDate: future,
            endDate: calendar.date(byAdding: .day, value: 4, to: Date())!
        )
        #expect(!inactiveOnMap.shouldShowOnMap)

        let activeNotOnMap = SurveysTestHelpers.makeSurvey(
            showOnMap: false,
            startDate: past,
            endDate: future
        )
        #expect(!activeNotOnMap.shouldShowOnMap)
    }

    // MARK: - Survey Visibility: Stops

    @Test func `shouldShowOnStop returns false when survey is inactive`() {
        let future = Calendar.current.date(byAdding: .day, value: 5, to: Date())!
        let survey = SurveysTestHelpers.makeSurvey(
            showOnStops: true,
            startDate: future,
            visibleStopsList: ["stop_1", "stop_2"]
        )
        #expect(!survey.shouldShowOnStop("stop_1"))
    }

    @Test func `shouldShowOnStop returns false when showOnStops is false`() {
        let survey = SurveysTestHelpers.makeSurvey(
            showOnStops: false,
            startDate: nil,
            endDate: nil,
            visibleStopsList: ["stop_1"]
        )
        #expect(!survey.shouldShowOnStop("stop_1"))
    }

    @Test func `shouldShowOnStop allows all stops when visibleStopsList is nil or empty`() {
        let surveyNilList = SurveysTestHelpers.makeSurvey(
            showOnStops: true,
            visibleStopsList: nil
        )
        #expect(surveyNilList.shouldShowOnStop("any_stop_id"))

        let surveyEmptyList = SurveysTestHelpers.makeSurvey(
            showOnStops: true,
            visibleStopsList: []
        )
        #expect(surveyEmptyList.shouldShowOnStop("any_stop_id"))
    }

    @Test func `shouldShowOnStop filters by visibleStopsList membership`() {
        let survey = SurveysTestHelpers.makeSurvey(
            showOnStops: true,
            visibleStopsList: ["stop_100", "stop_200"]
        )
        #expect(survey.shouldShowOnStop("stop_100"))
        #expect(survey.shouldShowOnStop("stop_200"))
        #expect(!survey.shouldShowOnStop("stop_300"))
    }

    // MARK: - Survey Visibility: Routes

    @Test func `shouldShowOnRoute returns false when survey is inactive`() {
        let past = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let expired = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        let survey = SurveysTestHelpers.makeSurvey(
            showOnStops: true,
            startDate: past,
            endDate: expired,
            visibleRoutesList: ["route_44"]
        )
        #expect(!survey.shouldShowOnRoute("route_44"))
    }

    @Test func `shouldShowOnRoute returns false when showOnStops is false`() {
        let survey = SurveysTestHelpers.makeSurvey(
            showOnStops: false,
            visibleRoutesList: ["route_44"]
        )
        #expect(!survey.shouldShowOnRoute("route_44"))
    }

    @Test func `shouldShowOnRoute allows all routes when visibleRoutesList is nil or empty`() {
        let surveyNilList = SurveysTestHelpers.makeSurvey(
            showOnStops: true,
            visibleRoutesList: nil
        )
        #expect(surveyNilList.shouldShowOnRoute("any_route_id"))

        let surveyEmptyList = SurveysTestHelpers.makeSurvey(
            showOnStops: true,
            visibleRoutesList: []
        )
        #expect(surveyEmptyList.shouldShowOnRoute("any_route_id"))
    }

    @Test func `shouldShowOnRoute filters by visibleRoutesList membership`() {
        let survey = SurveysTestHelpers.makeSurvey(
            showOnStops: true,
            visibleRoutesList: ["route_44", "route_E_Line"]
        )
        #expect(survey.shouldShowOnRoute("route_44"))
        #expect(survey.shouldShowOnRoute("route_E_Line"))
        #expect(!survey.shouldShowOnRoute("route_7"))
    }

    // MARK: - Survey Submission Serialization

    @Test func `SurveySubmission encodes all optional metadata correctly`() throws {
        let submission = SurveySubmission(
            userIdentifier: "user_uuid_999",
            surveyId: 42,
            stopIdentifier: "stop_12345",
            stopLongitude: -122.3321,
            stopLatitude: 47.6062,
            responses: [
                QuestionAnswerSubmission(
                    questionId: 101,
                    questionType: "text",
                    questionLabel: "Feedback",
                    answer: "Great service"
                ),
                QuestionAnswerSubmission(
                    questionId: 102,
                    questionType: "radio",
                    questionLabel: "Rating",
                    answer: "5"
                )
            ]
        )

        let encoded = try JSONEncoder().encode(submission)
        let root = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect(root["user_identifier"] as? String == "user_uuid_999")
        #expect(root["survey_id"] as? Int == 42)
        #expect(root["stop_identifier"] as? String == "stop_12345")
        #expect(root["stop_longitude"] as? Double == -122.3321)
        #expect(root["stop_latitude"] as? Double == 47.6062)

        // The responses field must be serialized as a JSON string
        let responsesString = try #require(root["responses"] as? String)
        let parsedResponses = try #require(try JSONSerialization.jsonObject(with: Data(responsesString.utf8)) as? [[String: Any]])
        #expect(parsedResponses.count == 2)
        #expect(parsedResponses[0]["question_id"] as? Int == 101)
        #expect(parsedResponses[0]["question_type"] as? String == "text")
        #expect(parsedResponses[0]["question_label"] as? String == "Feedback")
        #expect(parsedResponses[0]["answer"] as? String == "Great service")
        #expect(parsedResponses[1]["question_id"] as? Int == 102)
        #expect(parsedResponses[1]["answer"] as? String == "5")
    }

    @Test func `SurveySubmission omits nil optional fields during encoding`() throws {
        let submission = SurveySubmission(
            userIdentifier: "user_uuid_simple",
            surveyId: 7,
            stopIdentifier: nil,
            stopLongitude: nil,
            stopLatitude: nil,
            responses: [
                QuestionAnswerSubmission(
                    questionId: 1,
                    questionType: "text",
                    questionLabel: "Comment",
                    answer: "None"
                )
            ]
        )

        let encoded = try JSONEncoder().encode(submission)
        let root = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect(root["user_identifier"] as? String == "user_uuid_simple")
        #expect(root["survey_id"] as? Int == 7)
        #expect(root["stop_identifier"] == nil)
        #expect(root["stop_longitude"] == nil)
        #expect(root["stop_latitude"] == nil)
        #expect(root["responses"] != nil)
    }

    @Test func `QuestionAnswerSubmission equality and hashing`() {
        let ans1 = QuestionAnswerSubmission(questionId: 1, questionType: "radio", questionLabel: "L", answer: "A")
        let ans2 = QuestionAnswerSubmission(questionId: 1, questionType: "radio", questionLabel: "L", answer: "A")
        let ans3 = QuestionAnswerSubmission(questionId: 2, questionType: "radio", questionLabel: "L", answer: "A")

        #expect(ans1 == ans2)
        #expect(ans1.hashValue == ans2.hashValue)
        #expect(ans1 != ans3)
    }

    // MARK: - Survey Submission Response Decoding

    @Test func `SurveySubmissionResponse decodes nested dictionary correctly`() throws {
        let json = """
        {
            "survey_response": {
                "id": "response_abc_123",
                "update_path": "/api/v1/survey_responses/response_abc_123",
                "user_identifier": "user_xyz_789"
            }
        }
        """
        let response = try JSONDecoder().decode(SurveySubmissionResponse.self, from: Data(json.utf8))

        #expect(response.id == "response_abc_123")
        #expect(response.updatePath == "/api/v1/survey_responses/response_abc_123")
        #expect(response.userIdentifier == "user_xyz_789")
    }

    @Test func `SurveySubmissionResponse memberwise initializer and equality`() {
        let resp1 = SurveySubmissionResponse(
            id: "id_1",
            updatePath: "/path/1",
            userIdentifier: "user_1"
        )
        let resp2 = SurveySubmissionResponse(
            id: "id_1",
            updatePath: "/path/1",
            userIdentifier: "user_1"
        )
        let resp3 = SurveySubmissionResponse(
            id: "id_2",
            updatePath: "/path/2",
            userIdentifier: "user_2"
        )

        #expect(resp1 == resp2)
        #expect(resp1.hashValue == resp2.hashValue)
        #expect(resp1 != resp3)
    }

    @Test func `SurveySubmissionResponse throws when root key is missing`() {
        let malformedJson = """
        {
            "id": "response_abc_123",
            "update_path": "/api/v1/survey_responses/response_abc_123",
            "user_identifier": "user_xyz_789"
        }
        """
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(SurveySubmissionResponse.self, from: Data(malformedJson.utf8))
        }
    }
}
