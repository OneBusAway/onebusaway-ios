//
//  SurveySubmission.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

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

public struct SurveySubmissionResponse: Codable, Hashable {

    public let id: String

    public let updatePath: String

    public let userIdentifier: String

    enum CodingKeys: String, CodingKey {
        case id
        case updatePath = "update_path"
        case userIdentifier = "user_identifier"
    }

    public func surveyPathId() -> String {
        return updatePath.split(separator: "/").last.map(String.init) ?? ""
    }

}
