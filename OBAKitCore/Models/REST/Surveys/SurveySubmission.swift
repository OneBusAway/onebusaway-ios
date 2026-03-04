//
//  SurveySubmission.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Alias for UI layer compatibility
public typealias SurveyQuestionResponse = QuestionAnswerSubmission

public struct SurveySubmission: Codable, Hashable {

    public let userIdentifier: String

    public let surveyId: Int

    public let stopIdentifier: String?

    public let stopLongitude: Double?

    public let stopLatitude: Double?

    public let responses: [QuestionAnswerSubmission]

    public init(
        userIdentifier: String,
        surveyId: Int,
        stopIdentifier: String? = nil,
        stopLongitude: Double? = nil,
        stopLatitude: Double? = nil,
        responses: [QuestionAnswerSubmission]
    ) {
        self.userIdentifier = userIdentifier
        self.surveyId = surveyId
        self.stopIdentifier = stopIdentifier
        self.stopLongitude = stopLongitude
        self.stopLatitude = stopLatitude
        self.responses = responses
    }

    enum CodingKeys: String, CodingKey {
        case userIdentifier = "user_identifier"
        case surveyId = "survey_id"
        case stopIdentifier = "stop_identifier"
        case stopLongitude = "stop_longitude"
        case stopLatitude = "stop_latitude"
        case responses
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userIdentifier, forKey: .userIdentifier)
        try container.encode(surveyId, forKey: .surveyId)
        try container.encodeIfPresent(stopIdentifier, forKey: .stopIdentifier)
        try container.encodeIfPresent(stopLongitude, forKey: .stopLongitude)
        try container.encodeIfPresent(stopLatitude, forKey: .stopLatitude)

        // Server expects responses as a JSON string, not a nested array
        let responsesData = try JSONEncoder().encode(responses)
        let responsesString = String(data: responsesData, encoding: .utf8) ?? "[]"
        try container.encode(responsesString, forKey: .responses)
    }

}

public struct QuestionAnswerSubmission: Codable, Hashable {

    public let questionId: Int

    public let questionType: String

    public let questionLabel: String

    public let answer: String

    public init(questionId: Int, questionType: String, questionLabel: String, answer: String) {
        self.questionId = questionId
        self.questionType = questionType
        self.questionLabel = questionLabel
        self.answer = answer
    }

    enum CodingKeys: String, CodingKey {
        case questionId = "question_id"
        case questionType = "question_type"
        case questionLabel = "question_label"
        case answer
    }

}

public struct SurveySubmissionResponse: Hashable, Decodable {

    public let id: String

    public let updatePath: String

    public let userIdentifier: String

    public init(id: String, updatePath: String, userIdentifier: String) {
        self.id = id
        self.updatePath = updatePath
        self.userIdentifier = userIdentifier
    }

    private enum RootKeys: String, CodingKey {
        case surveyResponse = "survey_response"
    }

    private enum NestedKeys: String, CodingKey {
        case id
        case updatePath = "update_path"
        case userIdentifier = "user_identifier"
    }

    public init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: RootKeys.self)
        let nested = try root.nestedContainer(keyedBy: NestedKeys.self, forKey: .surveyResponse)
        self.id = try nested.decode(String.self, forKey: .id)
        self.updatePath = try nested.decode(String.self, forKey: .updatePath)
        self.userIdentifier = try nested.decode(String.self, forKey: .userIdentifier)
    }
}
