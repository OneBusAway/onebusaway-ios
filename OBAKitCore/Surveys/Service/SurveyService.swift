//
//  SurveyService.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Consolidated service for survey fetching, prioritization, state management, and submission.
@MainActor
public final class SurveyService: ObservableObject {

    // MARK: - Published State

    /// All surveys fetched from the backend.
    @Published public private(set) var allSurveys: [Survey] = []

    /// Surveys currently active based on date constraints.
    @Published public private(set) var visibleSurveys: [Survey] = []

    /// Whether surveys are currently being loaded.
    @Published public private(set) var isLoading: Bool = false

    /// Last error that occurred during survey operations.
    @Published public private(set) var lastError: Error?

    // MARK: - Dependencies

    private let apiService: RESTAPIService?
    private let userDataStore: UserDataStore

    // MARK: - Constants

    private let surveyLaunchInterval = 3

    // MARK: - Initialization

    public nonisolated init(apiService: RESTAPIService?, userDataStore: UserDataStore) {
        self.apiService = apiService
        self.userDataStore = userDataStore
    }

    // MARK: - Fetching

    /// Fetches surveys from the API for the current user.
    public func fetchSurveys() async {
        guard !isLoading else {
            Logger.info("fetchSurveys skipped: already loading")
            return
        }

        guard let apiService = apiService else {
            Logger.error("fetchSurveys called but apiService is nil")
            lastError = APIError.surveyServiceNotConfigured
            return
        }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let userID = userDataStore.surveyUserIdentifier
            let response = try await apiService.getSurveys(userID: userID)

            allSurveys = response.entry.surveys
            updateVisibleSurveys()
        } catch {
            Logger.error("Failed to fetch surveys: \(error)")
            lastError = error
            if allSurveys.isEmpty {
                visibleSurveys = []
            }
        }
    }

    // MARK: - Survey Finding

    /// Finds the appropriate survey to show for a specific stop.
    public func findSurveyForStop(stopID: String, routeIDs: [String]) -> Survey? {
        return findSurvey(isVisibleOnStop: true, stopID: stopID, routeIDs: routeIDs)
    }

    /// Finds the appropriate survey to show on the map.
    public func findSurveyForMap() -> Survey? {
        return findSurvey(isVisibleOnStop: false, stopID: nil, routeIDs: [])
    }

    // MARK: - Survey Gating

    /// Determines whether a survey should be shown based on launch count and reminder date.
    public func shouldShowSurvey() -> Bool {
        guard userDataStore.isSurveyEnabled else { return false }

        let launchCount = userDataStore.appLaunchCount
        guard launchCount > 0 && launchCount % surveyLaunchInterval == 0 else {
            return false
        }

        if let reminderDate = userDataStore.nextSurveyReminderDate, reminderDate > Date.now {
            return false
        }

        return true
    }

    /// Sets the next reminder date for showing surveys (3 days from now).
    public func setNextReminderDate() {
        let nextDate = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date().addingTimeInterval(86400 * 3)
        userDataStore.nextSurveyReminderDate = nextDate
    }

    // MARK: - State Management

    /// Marks a survey as completed.
    public func markSurveyCompleted(_ survey: Survey) {
        let userID = userDataStore.surveyUserIdentifier
        userDataStore.markSurveyCompleted(surveyId: survey.id, userIdentifier: userID)
        updateVisibleSurveys()
    }

    /// Marks a survey to be shown later.
    public func markSurveyForLater(_ survey: Survey) {
        let userID = userDataStore.surveyUserIdentifier
        userDataStore.markSurveyForLater(surveyId: survey.id, userIdentifier: userID)
        updateVisibleSurveys()
    }

    /// Dismisses a survey (same as completing it for display purposes).
    public func dismissSurvey(_ survey: Survey) {
        markSurveyCompleted(survey)
    }

    // MARK: - Submission

    /// Submits a hero question response.
    /// - Returns: Submission response with update path for additional questions.
    public func submitHeroQuestion(
        survey: Survey,
        heroQuestionResponse: SurveyQuestionResponse,
        stopID: String? = nil,
        stopLocation: (latitude: Double, longitude: Double)? = nil
    ) async throws -> SurveySubmissionResponse {
        guard let apiService = apiService else {
            throw APIError.surveyServiceNotConfigured
        }

        let userID = userDataStore.surveyUserIdentifier

        let submission = SurveySubmission(
            userIdentifier: userID,
            surveyId: survey.id,
            stopIdentifier: stopID,
            stopLongitude: stopLocation?.longitude,
            stopLatitude: stopLocation?.latitude,
            responses: [heroQuestionResponse]
        )

        let response = try await apiService.submitSurveyResponse(submission)
        return response.entry
    }

    /// Submits additional questions for an existing survey response.
    /// - Returns: Updated submission response.
    public func submitAdditionalQuestions(
        responseID: String,
        additionalResponses: [SurveyQuestionResponse]
    ) async throws -> SurveySubmissionResponse {
        guard let apiService = apiService else {
            throw APIError.surveyServiceNotConfigured
        }

        let response = try await apiService.updateSurveyResponse(
            responseID: responseID,
            additionalResponses: additionalResponses
        )
        return response.entry
    }

    // MARK: - Helpers

    /// Creates a question response for a given question and answer.
    public func createQuestionResponse(question: SurveyQuestion, answer: String) -> SurveyQuestionResponse {
        return SurveyQuestionResponse(
            questionId: question.id,
            questionType: question.content.typeString,
            questionLabel: question.content.displayText,
            answer: answer
        )
    }

    /// Formats multiple checkbox selections into a JSON array string.
    public func formatCheckboxAnswer(_ selections: [String]) -> String {
        do {
            let jsonData = try JSONEncoder().encode(selections)
            guard let result = String(data: jsonData, encoding: .utf8) else {
                Logger.error("formatCheckboxAnswer: UTF-8 encoding failed for \(selections.count) selections")
                return "[]"
            }
            return result
        } catch {
            Logger.error("Failed to encode checkbox selections: \(error)")
            return "[]"
        }
    }

    // MARK: - Private: Visibility Filtering

    private func updateVisibleSurveys() {
        visibleSurveys = allSurveys.filter { $0.isActive }
    }

    // MARK: - Private: Survey Finding

    private enum SurveyPriorityResult {
        case returnImmediately(Survey)
        case setAlwaysVisible(Int)
        case setOneTime(Int)
        case `continue`
    }

    private func findSurvey(isVisibleOnStop: Bool, stopID: String?, routeIDs: [String]) -> Survey? {
        let surveys = allSurveys
        guard !surveys.isEmpty else { return nil }

        let userID = userDataStore.surveyUserIdentifier
        var alwaysVisibleIndex: Int = -1
        var oneTimeSurveyIndex: Int = -1

        for (index, survey) in surveys.enumerated() {
            guard !survey.questions.isEmpty else { continue }
            guard checkSurveyVisibility(survey: survey, isVisibleOnStop: isVisibleOnStop, stopID: stopID, routeIDs: routeIDs) else { continue }

            let priorityResult = applySurveyPriorityLogic(survey: survey, userID: userID, index: index)

            switch priorityResult {
            case .returnImmediately(let survey):
                return survey
            case .setAlwaysVisible(let idx) where alwaysVisibleIndex == -1:
                alwaysVisibleIndex = idx
            case .setOneTime(let idx) where oneTimeSurveyIndex == -1:
                oneTimeSurveyIndex = idx
            default:
                continue
            }
        }

        if oneTimeSurveyIndex != -1 {
            return surveys[oneTimeSurveyIndex]
        } else if alwaysVisibleIndex != -1 {
            return surveys[alwaysVisibleIndex]
        }

        return nil
    }

    private func checkSurveyVisibility(survey: Survey, isVisibleOnStop: Bool, stopID: String?, routeIDs: [String]) -> Bool {
        if isVisibleOnStop {
            return checkStopVisibility(survey: survey, stopID: stopID, routeIDs: routeIDs)
        } else {
            return survey.shouldShowOnMap
        }
    }

    private func checkStopVisibility(survey: Survey, stopID: String?, routeIDs: [String]) -> Bool {
        guard survey.showOnStops else { return false }
        guard let stopID = stopID else { return true }

        if survey.shouldShowOnStop(stopID) {
            return true
        }

        return routeIDs.contains { routeID in
            survey.shouldShowOnRoute(routeID)
        }
    }

    private func applySurveyPriorityLogic(survey: Survey, userID: String, index: Int) -> SurveyPriorityResult {
        let isSurveyCompleted = userDataStore.isSurveyCompleted(surveyId: survey.id, userIdentifier: userID)

        if survey.alwaysVisible {
            if survey.allowsMultipleResponses {
                return .setAlwaysVisible(index)
            } else {
                return isSurveyCompleted ? .continue : .returnImmediately(survey)
            }
        } else {
            if !isSurveyCompleted {
                return .setOneTime(index)
            } else if userDataStore.shouldShowSurveyLater(surveyId: survey.id, userIdentifier: userID) {
                return .setOneTime(index)
            } else {
                return .continue
            }
        }
    }
}
