//
//  Survey.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Top-level response containing surveys and region metadata.
public struct StudyResponse: Codable, Hashable {

    public let surveys: [Survey]

    public let region: SurveyRegion

}

public struct SurveyRegion: Codable, Hashable {
    public let id: Int
    public let name: String
}

public struct Survey: Codable, Hashable {

    public let id: Int

    public let name: String

    public let createdAt: Date

    public let updatedAt: Date

    public let showOnMap: Bool

    public let showOnStops: Bool

    public let startDate: Date?

    public let endDate: Date?

    public let visibleStopsList: [String]?

    public let visibleRoutesList: [String]?

    public let allowsMultipleResponses: Bool

    public let alwaysVisible: Bool

    public let study: Study

    public let questions: [SurveyQuestion]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case showOnMap = "show_on_map"
        case showOnStops = "show_on_stops"
        case startDate = "start_date"
        case endDate = "end_date"
        case visibleStopsList = "visible_stop_list"
        case visibleRoutesList = "visible_route_list"
        case allowsMultipleResponses = "allows_multiple_responses"
        case alwaysVisible = "always_visible"
        case study
        case questions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        showOnMap = try container.decodeIfPresent(Bool.self, forKey: .showOnMap) ?? false
        showOnStops = try container.decodeIfPresent(Bool.self, forKey: .showOnStops) ?? false
        startDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        visibleStopsList = try container.decodeIfPresent([String].self, forKey: .visibleStopsList)
        visibleRoutesList = try container.decodeIfPresent([String].self, forKey: .visibleRoutesList)
        allowsMultipleResponses = try container.decodeIfPresent(Bool.self, forKey: .allowsMultipleResponses) ?? false
        alwaysVisible = try container.decodeIfPresent(Bool.self, forKey: .alwaysVisible) ?? false
        study = try container.decode(Study.self, forKey: .study)
        questions = try container.decode([SurveyQuestion].self, forKey: .questions)
    }

    public init(id: Int, name: String, createdAt: Date, updatedAt: Date, showOnMap: Bool, showOnStops: Bool, startDate: Date?, endDate: Date?, visibleStopsList: [String]?, visibleRoutesList: [String]?, allowsMultipleResponses: Bool, alwaysVisible: Bool, study: Study, questions: [SurveyQuestion]) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.showOnMap = showOnMap
        self.showOnStops = showOnStops
        self.startDate = startDate
        self.endDate = endDate
        self.visibleStopsList = visibleStopsList
        self.visibleRoutesList = visibleRoutesList
        self.allowsMultipleResponses = allowsMultipleResponses
        self.alwaysVisible = alwaysVisible
        self.study = study
        self.questions = questions
    }
}

extension Survey: Identifiable { }

extension Survey {

    /// Returns an array of survey questions whose content is valid (non-nil) based on their type.
    public func getQuestions() -> [SurveyQuestion] {

        return questions.filter {
            switch $0.content.type {
            case .text:
                return $0.content.asTextContent != nil
            case .radio, .checkbox:
                return $0.content.asSelectableContent != nil
            case .label:
                return $0.content.asLabelContent != nil
            case .externalSurvey:
                return $0.content.asExternalSurveyContent != nil
            }
        }
    }

    /// Returns the first question (hero question) if it exists
    public var heroQuestion: SurveyQuestion? {
        return questions.first { $0.position == 1 }
    }

    /// Returns all questions except the hero question
    public var remainingQuestions: [SurveyQuestion] {
        guard let hero = heroQuestion else { return questions }
        return questions.filter { $0.id != hero.id }
    }

    /// Returns true if the survey is currently active (within date range)
    public var isActive: Bool {
        let now = Date()
        if let startDate = startDate, now < startDate { return false }
        if let endDate = endDate, now > endDate { return false }
        return true
    }

    /// Returns true if the survey should be shown on the specified stop.
    /// Checks `showOnStops` and `isActive` before matching the stop list.
    public func shouldShowOnStop(_ stopID: String) -> Bool {
        guard showOnStops, isActive else { return false }
        guard let visibleStops = visibleStopsList else { return true }
        return visibleStops.contains(stopID)
    }

    /// Returns true if the survey should be shown for the specified route.
    /// Checks `showOnStops` and `isActive` before matching the route list.
    public func shouldShowOnRoute(_ routeID: String) -> Bool {
        guard showOnStops, isActive else { return false }
        guard let visibleRoutes = visibleRoutesList else { return true }
        return visibleRoutes.contains(routeID)
    }

    /// Returns true if the survey should be shown on the map
    public var shouldShowOnMap: Bool {
        return showOnMap && isActive
    }

}

public struct Study: Codable, Hashable {

    public let id: Int

    public let name: String

    public let description: String?

    public init(id: Int, name: String, description: String?) {
        self.id = id
        self.name = name
        self.description = description
    }

}

// MARK: - Survey Question
public struct SurveyQuestion: Codable, Hashable {

    public let id: Int

    public let position: Int

    public let required: Bool

    public let content: QuestionContent

    public init(id: Int, position: Int, required: Bool, content: QuestionContent) {
        self.id = id
        self.position = position
        self.required = required
        self.content = content
    }

}

// MARK: - Question Content
public struct QuestionContent: Codable, Hashable {

    public let labelText: String

    public let type: QuestionType

    public let options: [String]?

    public let url: String?

    public let surveyProvider: String?

    public let embeddedDataFields: [String]?

    enum CodingKeys: String, CodingKey {
        case labelText = "label_text"
        case type
        case options
        case url
        case surveyProvider = "survey_provider"
        case embeddedDataFields = "embedded_data_fields"
    }

    public init(labelText: String, type: QuestionType, options: [String]? = nil, url: String? = nil, surveyProvider: String? = nil, embeddedDataFields: [String]? = nil) {
        self.labelText = labelText
        self.type = type
        self.options = options
        self.url = url
        self.surveyProvider = surveyProvider
        self.embeddedDataFields = embeddedDataFields
    }
}

extension QuestionContent {

    var asTextContent: String? {
        guard type == .text else { return nil }
        return labelText
    }

    var asSelectableContent: SelectableContent? {
        guard type == .checkbox || type == .radio else { return nil }
        return SelectableContent(labelText: labelText, options: options)
    }

    var asLabelContent: TextContent? {
        guard type == .label else { return nil }
        return TextContent(labelText: labelText)
    }

    var asExternalSurveyContent: ExternalSurveyContent? {
        guard type == .externalSurvey else { return nil }
        return ExternalSurveyContent(
            labelText: labelText,
            url: url,
            provider: surveyProvider,
            embeddedDataFields: embeddedDataFields
        )
    }

}

// MARK: - Question Content Type
public enum QuestionType: String, Codable, Hashable {

    case text = "text"

    case radio = "radio"

    case checkbox = "checkbox"

    case label = "label"

    case externalSurvey = "external_survey"

}

// MARK: - Question Content Models
public struct TextContent: Codable, Hashable {
    public let labelText: String
}

public struct SelectableContent: Codable, Hashable {
    public let labelText: String
    public let options: [String]?
}

public struct ExternalSurveyContent: Codable, Hashable {
    public let labelText: String
    public let url: String?
    public let provider: String?
    public let embeddedDataFields: [String]?
}

// MARK: - QuestionContent Compatibility

extension QuestionContent {
    /// Display text for UI layer compatibility
    public var displayText: String { labelText }
    /// Type string for API submission compatibility
    public var typeString: String { type.rawValue }
}
