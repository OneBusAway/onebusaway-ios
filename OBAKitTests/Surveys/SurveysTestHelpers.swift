//
//  SurveyVMTestHelpers.swift
//  OBAKit
//
//  Created by Mohamed Sliem on 19/02/2026.
//

import Foundation
@testable import OBAKitCore

enum SurveysTestHelpers {

    // MARK: - Study

    static func makeStudy(
        id: Int = 1,
        name: String = "Test Study",
        description: String? = nil
    ) -> Study {
        Study(id: id, name: name, description: description)
    }

    // MARK: - QuestionContent

    static func makeQuestionContent(
        type: QuestionType = .text,
        labelText: String = "Test Question",
        options: [String]? = nil,
        url: String? = nil,
        surveyProvider: String? = nil,
        embeddedDataFields: [String]? = nil
    ) -> QuestionContent {
        QuestionContent(
            labelText: labelText,
            type: type,
            options: options,
            url: url,
            surveyProvider: surveyProvider,
            embeddedDataFields: embeddedDataFields
        )
    }

    // MARK: - SurveyQuestion

    static func makeSurveyQuestion(
        id: Int = 1,
        position: Int = 0,
        required: Bool = false,
        type: QuestionType = .text,
        labelText: String = "Test Question",
        options: [String]? = nil,
        url: String? = nil,
        embeddedDataFields: [String] = []
    ) -> SurveyQuestion {
        SurveyQuestion(
            id: id,
            position: position,
            required: required,
            content: makeQuestionContent(
                type: type,
                labelText: labelText,
                options: options,
                url: url,
                embeddedDataFields: embeddedDataFields
            )
        )
    }

    // MARK: - Survey

    static func makeSurvey(
        id: Int = 1,
        name: String = "Test Survey",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        showOnMap: Bool = true,
        showOnStops: Bool = false,
        startDate: Date? = nil,
        endDate: Date? = nil,
        visibleStopsList: [String]? = nil,
        visibleRoutesList: [String]? = nil,
        allowsMultipleResponses: Bool = false,
        allowsVisible: Bool = false,
        study: Study? = nil,
        questions: [SurveyQuestion]? = nil
    ) -> Survey {
        Survey(
            id: id,
            name: name,
            createdAt: createdAt,
            updatedAt: updatedAt,
            showOnMap: showOnMap,
            showOnStops: showOnStops,
            startDate: startDate,
            endDate: endDate,
            visibleStopsList: visibleStopsList,
            visibleRoutesList: visibleRoutesList,
            allowsMultipleResponses: allowsMultipleResponses,
            allowsVisible: allowsVisible,
            study: study ?? makeStudy(),
            questions: questions ?? [makeSurveyQuestion()]
        )
    }

    // MARK: - Stop

    static func makeStop(id: String = "stop-1", routeIDs: [String] = []) -> Stop {
        let routeIdsJSON = routeIDs.map { "\"\($0)\"" }.joined(separator: ", ")
        let json = """
        {
            "code": "\(id)",
            "direction": "N",
            "id": "\(id)",
            "lat": 0.0,
            "lon": 0.0,
            "locationType": 0,
            "name": "Test Stop",
            "routeIds": [\(routeIdsJSON)],
            "wheelchairBoarding": "unknown"
        }
        """.data(using: .utf8)!
        let stop = try! JSONDecoder().decode(Stop.self, from: json)
        stop.routes = []
        return stop
    }
}
