//
//  Survey.swift
//  OBAKitCore
//
//  Created by Mohamed Sliem on 09/11/2025.
//

import Foundation

/// Represents a Study surveys response containing the survey data  with associated information
public struct StudyResponse: Codable, Hashable {

    public let surveys: [Survey]

    public let region: Region

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

    public let allowsVisible: Bool

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
        case allowsVisible = "allows_visible"
        case study
        case questions
    }

}

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

}

public struct Study: Codable, Hashable {

    public let id: Int

    public let name: String

    public let description: String?

}

// MARK: - Survey Question
public struct SurveyQuestion: Codable, Hashable {

    public let id: Int

    public let position: Int

    public let required: Bool

    public let content: QuestionContent

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
struct TextContent: Codable, Hashable {
    let labelText: String
}

struct SelectableContent: Codable, Hashable {
    let labelText: String
    let options: [String]?
}

struct ExternalSurveyContent: Codable, Hashable {
    let labelText: String
    let url: String?
    let provider: String?
    let embeddedDataFields: [String]?
}
