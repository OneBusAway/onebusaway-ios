//
//  SurveyServiceProtocol.swift
//  OBAKitCore
//
//  Created by Mohamed Sliem on 28/11/2025.
//

import Foundation

public protocol SurveyServiceProtocol {

    var surveys: [Survey] { get }

    func fetchSurveys() async throws

    func submitSurveyResponse(
        surveyId: Int,
        stopIdentifier: String?,
        stopLongitude: Double?,
        stopLatitude: Double?,
        _ response: QuestionAnswerSubmission
    ) async throws

    func updateSurveyResponses(
        surveyId: Int,
        stopIdentifier: String?,
        stopLongitude: Double?,
        stopLatitude: Double?,
        _ responses: [QuestionAnswerSubmission]
    ) async throws

}
