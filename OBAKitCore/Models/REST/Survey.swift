//
//  Survey.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

// MARK: - Survey Question Content Types

/// Represents the different types of question content that can be displayed in a survey
public enum SurveyQuestionContent: Codable, Hashable {
    case label(text: String)
    case radio(labelText: String, options: [String])
    case checkbox(labelText: String, options: [String])
    case text(labelText: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case labelText = "label_text"
        case options
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "label":
            let text = try container.decode(String.self, forKey: .labelText)
            self = .label(text: text)
        case "radio":
            let labelText = try container.decode(String.self, forKey: .labelText)
            let options = try container.decode([String].self, forKey: .options)
            self = .radio(labelText: labelText, options: options)
        case "checkbox":
            let labelText = try container.decode(String.self, forKey: .labelText)
            let options = try container.decode([String].self, forKey: .options)
            self = .checkbox(labelText: labelText, options: options)
        case "text":
            let labelText = try container.decode(String.self, forKey: .labelText)
            self = .text(labelText: labelText)
        default:
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown question type: \(type)"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .label(let text):
            try container.encode("label", forKey: .type)
            try container.encode(text, forKey: .labelText)
        case .radio(let labelText, let options):
            try container.encode("radio", forKey: .type)
            try container.encode(labelText, forKey: .labelText)
            try container.encode(options, forKey: .options)
        case .checkbox(let labelText, let options):
            try container.encode("checkbox", forKey: .type)
            try container.encode(labelText, forKey: .labelText)
            try container.encode(options, forKey: .options)
        case .text(let labelText):
            try container.encode("text", forKey: .type)
            try container.encode(labelText, forKey: .labelText)
        }
    }

    /// Returns the display text for this question content
    public var displayText: String {
        switch self {
        case .label(let text):
            return text
        case .radio(let labelText, _):
            return labelText
        case .checkbox(let labelText, _):
            return labelText
        case .text(let labelText):
            return labelText
        }
    }

    /// Returns the question type as a string for API submission
    public var typeString: String {
        switch self {
        case .label: return "label"
        case .radio: return "radio"
        case .checkbox: return "checkbox"
        case .text: return "text"
        }
    }
}

// MARK: - Survey Question

/// Represents a single question in a survey
public struct SurveyQuestion: Codable, Hashable, Identifiable {
    public let id: Int
    public let position: Int
    public let required: Bool
    public let content: SurveyQuestionContent

    public init(id: Int, position: Int, required: Bool, content: SurveyQuestionContent) {
        self.id = id
        self.position = position
        self.required = required
        self.content = content
    }

    /// Returns true if this question is the first question (hero question)
    public var isHeroQuestion: Bool {
        return position == 1
    }

    /// Returns true if this question can be skipped (not required)
    public var canBeSkipped: Bool {
        return !required
    }
}

// MARK: - Study

/// Represents a study that contains surveys
public struct Study: Codable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let description: String

    public init(id: Int, name: String, description: String) {
        self.id = id
        self.name = name
        self.description = description
    }
}

// MARK: - Survey

/// Represents a survey with its questions and visibility settings
public struct Survey: Codable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let createdAt: Date
    public let updatedAt: Date
    public let showOnMap: Bool
    public let showOnStops: Bool
    public let startDate: Date?
    public let endDate: Date?
    public let visibleStopList: [String]?
    public let visibleRouteList: [String]?
    public let allowsMultipleResponses: Bool
    public let alwaysVisible: Bool
    public let study: Study
    public let questions: [SurveyQuestion]

    private enum CodingKeys: String, CodingKey {
        case id, name, study, questions
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case showOnMap = "show_on_map"
        case showOnStops = "show_on_stops"
        case startDate = "start_date"
        case endDate = "end_date"
        case visibleStopList = "visible_stop_list"
        case visibleRouteList = "visible_route_list"
        case allowsMultipleResponses = "allows_multiple_responses"
        case alwaysVisible = "always_visible"
    }

    public init(id: Int, name: String, createdAt: Date, updatedAt: Date, showOnMap: Bool, showOnStops: Bool, startDate: Date?, endDate: Date?, visibleStopList: [String]?, visibleRouteList: [String]?, allowsMultipleResponses: Bool, alwaysVisible: Bool, study: Study, questions: [SurveyQuestion]) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.showOnMap = showOnMap
        self.showOnStops = showOnStops
        self.startDate = startDate
        self.endDate = endDate
        self.visibleStopList = visibleStopList
        self.visibleRouteList = visibleRouteList
        self.allowsMultipleResponses = allowsMultipleResponses
        self.alwaysVisible = alwaysVisible
        self.study = study
        self.questions = questions
    }

    /// Returns the first question (hero question) if it exists
    public var heroQuestion: SurveyQuestion? {
        return questions.first { $0.isHeroQuestion }
    }

    /// Returns all questions except the hero question
    public var remainingQuestions: [SurveyQuestion] {
        return questions.filter { !$0.isHeroQuestion }
    }

    /// Returns true if the survey is currently active (within date range)
    public var isActive: Bool {
        let now = Date()

        if let startDate = startDate, now < startDate {
            return false
        }

        if let endDate = endDate, now > endDate {
            return false
        }

        return true
    }

    /// Returns true if the survey should be shown on the specified stop
    public func shouldShowOnStop(_ stopID: String) -> Bool {
        guard showOnStops else { return false }
        guard isActive else { return false }

        // If no specific stops are listed, show on all stops
        guard let visibleStops = visibleStopList else { return true }

        return visibleStops.contains(stopID)
    }

    /// Returns true if the survey should be shown for the specified route
    public func shouldShowOnRoute(_ routeID: String) -> Bool {
        guard showOnStops else { return false }
        guard isActive else { return false }

        // If no specific routes are listed, show on all routes
        guard let visibleRoutes = visibleRouteList else { return true }

        return visibleRoutes.contains(routeID)
    }

    /// Returns true if the survey should be shown on the map
    public var shouldShowOnMap: Bool {
        return showOnMap && isActive
    }
}

// MARK: - Survey Response

/// Represents a response to a survey question
public struct SurveyQuestionResponse: Codable, Hashable {
    public let questionId: Int
    public let questionType: String
    public let questionLabel: String
    public let answer: String

    private enum CodingKeys: String, CodingKey {
        case questionId = "question_id"
        case questionType = "question_type"
        case questionLabel = "question_label"
        case answer
    }

    public init(questionId: Int, questionType: String, questionLabel: String, answer: String) {
        self.questionId = questionId
        self.questionType = questionType
        self.questionLabel = questionLabel
        self.answer = answer
    }
}

/// Represents a complete survey response submission
public struct SurveyResponse: Codable {
    public let userIdentifier: String
    public let surveyId: Int
    public let stopIdentifier: String?
    public let stopLatitude: Double?
    public let stopLongitude: Double?
    public let response: [SurveyQuestionResponse]

    private enum CodingKeys: String, CodingKey {
        case userIdentifier = "user_identifier"
        case surveyId = "survey_id"
        case stopIdentifier = "stop_identifier"
        case stopLatitude = "stop_latitude"
        case stopLongitude = "stop_longitude"
        case response
    }

    public init(userIdentifier: String, surveyId: Int, stopIdentifier: String?, stopLatitude: Double?, stopLongitude: Double?, response: [SurveyQuestionResponse]) {
        self.userIdentifier = userIdentifier
        self.surveyId = surveyId
        self.stopIdentifier = stopIdentifier
        self.stopLatitude = stopLatitude
        self.stopLongitude = stopLongitude
        self.response = response
    }
}

/// Represents the response from the survey submission API
public struct SurveySubmissionResponse: Codable {
    public let id: String
    public let updatePath: String
    public let userIdentifier: String

    private enum CodingKeys: String, CodingKey {
        case id
        case updatePath
        case userIdentifier
    }

    public init(id: String, updatePath: String, userIdentifier: String) {
        self.id = id
        self.updatePath = updatePath
        self.userIdentifier = userIdentifier
    }
}

// MARK: - Surveys API Response

/// Represents the response from the surveys API endpoint
public struct SurveysResponse: Codable {
    public let surveys: [Survey]
    public let region: SurveyRegion

    public init(surveys: [Survey], region: SurveyRegion) {
        self.surveys = surveys
        self.region = region
    }
}

/// Represents region information in the surveys response
public struct SurveyRegion: Codable {
    public let id: Int
    public let name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}
