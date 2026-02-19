//
//  MockSurveyService.swift
//  OBAKitTests
//
//  Created by Mohamed Sliem on 18/02/2026.
//

import OBAKitCore

final class MockSurveyService: SurveyServiceProtocol {
    var surveys: [Survey] = []

    var fetchSurveysCallCount = 0
    var fetchSurveysError: Error?

    var submitResponseCallCount = 0
    var lastSubmittedSurveyId: Int?
    var lastSubmittedStopId: String?
    var submitResponseError: Error?

    var updateResponseCallCount = 0
    var lastUpdatedSurveyId: Int?
    var updateResponseError: Error?

    /// Incremented after `fetchSurveys` fully completes (success or throw).
    /// Used by wait helpers to know the fetch task has actually finished.
    var fetchCompletedCallCount = 0

    /// Incremented after `submitSurveyResponse` fully completes (success or throw).
    var submitCompletedCallCount = 0

    /// Incremented after `updateSurveyResponses` fully completes (success or throw).
    var updateCompletedCallCount = 0

    func fetchSurveys() async throws {
        fetchSurveysCallCount += 1

        defer { fetchCompletedCallCount += 1 }

        if let error = fetchSurveysError {
            throw error
        }
    }

    func submitSurveyResponse(
        surveyId: Int,
        stopIdentifier: String?,
        stopLongitude: Double?,
        stopLatitude: Double?,
        _ response: QuestionAnswerSubmission
    ) async throws {
        submitResponseCallCount += 1
        lastSubmittedSurveyId = surveyId
        lastSubmittedStopId = stopIdentifier

        defer { submitCompletedCallCount += 1 }

        if let error = submitResponseError {
            throw error
        }
    }

    func updateSurveyResponses(
        surveyId: Int,
        stopIdentifier: String?,
        stopLongitude: Double?,
        stopLatitude: Double?,
        _ responses: [QuestionAnswerSubmission]
    ) async throws {
        updateResponseCallCount += 1
        lastUpdatedSurveyId = surveyId

        defer { updateCompletedCallCount += 1 }

        if let error = updateResponseError {
            throw error
        }
    }
}
