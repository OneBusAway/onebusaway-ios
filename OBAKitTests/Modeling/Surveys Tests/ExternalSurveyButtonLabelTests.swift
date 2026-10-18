//
//  ExternalSurveyButtonLabelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

/// `button_label` picks the call to action on an `external_survey` question.
/// It is an open set on the wire: an unknown value must fall back to Open
/// Survey rather than fail the survey payload, so the servers can add a label
/// without breaking shipped apps.
@Suite(.serialized)
struct ExternalSurveyButtonLabelTests {

    private func decodeContent(buttonLabel: String?) throws -> QuestionContent {
        var json: [String: Any] = [
            "type": "external_survey",
            "label_text": "Tell us about your trip",
            "url": "https://example.com/survey",
            "survey_provider": "qualtrics",
            "embedded_data_fields": ["user_id"]
        ]
        if let buttonLabel {
            json["button_label"] = buttonLabel
        }
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(QuestionContent.self, from: data)
    }

    @Test func `Content without button_label defaults to Open Survey`() throws {
        let content = try decodeContent(buttonLabel: nil)

        #expect(content.buttonLabel == nil)
        #expect(content.externalSurveyButtonLabel == .openSurvey)
    }

    @Test(arguments: [
        ("open_survey", ExternalSurveyButtonLabel.openSurvey),
        ("learn_more", .learnMore),
        ("share_feedback", .shareFeedback),
        ("sign_up", .signUp)
    ])
    func `Known button_label values decode`(key: String, expected: ExternalSurveyButtonLabel) throws {
        let content = try decodeContent(buttonLabel: key)

        #expect(content.buttonLabel == key)
        #expect(content.externalSurveyButtonLabel == expected)
    }

    @Test func `Unknown button_label decodes and falls back to Open Survey`() throws {
        let content = try decodeContent(buttonLabel: "book_a_ride")

        #expect(content.buttonLabel == "book_a_ride")
        #expect(content.externalSurveyButtonLabel == .openSurvey)
    }

    @Test func `A survey with an unknown button_label is still offered`() throws {
        let json = """
        {"id": 1, "position": 1, "required": false,
         "content": {"type": "external_survey", "label_text": "Hi", "url": "https://example.com", "button_label": "something_new"}}
        """
        let question = try JSONDecoder().decode(SurveyQuestion.self, from: Data(json.utf8))
        let survey = SurveysTestHelpers.makeSurvey(questions: [question])

        #expect(survey.getQuestions().count == 1)
        #expect(survey.isExternalSurvey)
    }
}
