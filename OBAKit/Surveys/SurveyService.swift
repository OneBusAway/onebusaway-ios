//
//  SurveyService.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// Service responsible for managing survey operations including fetching, visibility logic, and submission
@MainActor
public class SurveyService: ObservableObject {

    // MARK: - Properties

    private let apiService: RESTAPIService?
    private let userDataStore: UserDataStore
    private let currentRegionProvider: () -> Region?

    /// All surveys fetched from the API
    @Published public private(set) var allSurveys: [Survey] = []

    /// Surveys currently visible to the user based on context
    @Published public private(set) var visibleSurveys: [Survey] = []

    /// Whether surveys are currently being loaded
    @Published public private(set) var isLoading: Bool = false

    /// Last error that occurred during survey operations
    @Published public private(set) var lastError: Error?

    // MARK: - Initialization

    public init(apiService: RESTAPIService?, userDataStore: UserDataStore, currentRegionProvider: @escaping () -> Region?) {
        self.apiService = apiService
        self.userDataStore = userDataStore
        self.currentRegionProvider = currentRegionProvider
    }

    // MARK: - Survey Fetching

    /// Fetches surveys from the API for the current user
    public func fetchSurveys() async {
        guard let apiService = apiService else {
            lastError = APIError.surveyServiceNotConfigured
            return
        }

        isLoading = true
        lastError = nil

        do {
            let userID = userDataStore.surveyUserIdentifier
            let response = try await apiService.getSurveys(userID: userID)

            allSurveys = response.entry.surveys
            updateVisibleSurveys()

        } catch {
            lastError = error
            allSurveys = []
            visibleSurveys = []
        }

        isLoading = false
    }

    // MARK: - Survey Visibility Logic

    /// Updates surveys that are currently active based on date/time constraints
    private func updateVisibleSurveys() {
        visibleSurveys = allSurveys.filter { survey in
              survey.isActive
          }
    }

    /// Finds the appropriate survey to show for a specific stop
    /// Applies visibility rules, completion status, and priority logic
    /// - Parameter stopID: The ID of the stop
    /// - Parameter routeIDs: Route IDs that serve this stop
    /// - Returns: Survey to display, or nil if no survey should be shown
    public func findSurveyForStop(stopID: String, routeIDs: [String]) -> Survey? {
        return findSurvey(isVisibleOnStop: true, stopID: stopID, routeIDs: routeIDs)
    }

    /// Finds the appropriate survey to show on the map
    /// - Returns: Survey to display on map, or nil if no survey should be shown
    public func findSurveyForMap() -> Survey? {
        return findSurvey(isVisibleOnStop: false, stopID: nil, routeIDs: [])
    }

    /// Finds the highest priority survey that should be displayed to the user
    /// Returns the first survey that matches visibility rules and completion status
    private func findSurvey(isVisibleOnStop: Bool, stopID: String?, routeIDs: [String]) -> Survey? {
        let surveys = allSurveys

        guard !surveys.isEmpty else { return nil }

        let userID = userDataStore.surveyUserIdentifier
        var alwaysVisibleIndex: Int = -1
        var oneTimeSurveyIndex: Int = -1

        for (index, survey) in surveys.enumerated() {
            guard isValidSurvey(survey) else { continue }
            guard checkSurveyVisibility(survey: survey, isVisibleOnStop: isVisibleOnStop, stopID: stopID, routeIDs: routeIDs) else { continue }

            let priorityResult = applySurveyPriorityLogic(survey: survey, userID: userID, index: index)

            switch priorityResult {
            case .returnImmediately(let survey):
                return survey
            case .setAlwaysVisible(let index):
                alwaysVisibleIndex = index
            case .setOneTime(let index):
                oneTimeSurveyIndex = index
            case .continue:
                continue
            }
        }

        // Priority order: one-time surveys override always-visible surveys
        if oneTimeSurveyIndex != -1 {
            return surveys[oneTimeSurveyIndex]
        } else if alwaysVisibleIndex != -1 {
            return surveys[alwaysVisibleIndex]
        }

        return nil
    }

    // MARK: - Survey Finding Helper Methods

    private enum SurveyPriorityResult {
      case returnImmediately(Survey)
      case setAlwaysVisible(Int)
      case setOneTime(Int)
      case `continue`
    }

    /// Checks if survey has required questions to be displayable
    private func isValidSurvey(_ survey: Survey) -> Bool {
        return !survey.questions.isEmpty
    }

    /// Determines if survey meets location-based visibility requirements
    private func checkSurveyVisibility(survey: Survey, isVisibleOnStop: Bool, stopID: String?, routeIDs: [String]) -> Bool {
        if isVisibleOnStop {
            return checkStopVisibility(survey: survey, stopID: stopID, routeIDs: routeIDs)
        } else {
            return survey.shouldShowOnMap
        }
    }

    /// Validates survey visibility rules for stop-based display
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

    /// Determines survey priority based on completion status and response settings
    private func applySurveyPriorityLogic(survey: Survey, userID: String, index: Int) -> SurveyPriorityResult {
        let isSurveyCompleted = userDataStore.isSurveyCompleted(surveyId: survey.id, userIdentifier: userID)

        if survey.alwaysVisible {
            return handleAlwaysVisibleSurvey(survey: survey, isSurveyCompleted: isSurveyCompleted, index: index)
        } else {
            return handleRegularSurvey(survey: survey, userID: userID, isSurveyCompleted: isSurveyCompleted, index: index)
        }
    }

    /// Processes priority logic for surveys marked as always visible
    private func handleAlwaysVisibleSurvey(survey: Survey, isSurveyCompleted: Bool, index: Int) -> SurveyPriorityResult {
        if survey.allowsMultipleResponses {
            return .setAlwaysVisible(index)
        } else {
            if !isSurveyCompleted {
                return .returnImmediately(survey)
            } else {
                return .continue
            }
        }
    }

    /// Processes priority logic for standard one-time surveys
    private func handleRegularSurvey(survey: Survey, userID: String, isSurveyCompleted: Bool, index: Int) -> SurveyPriorityResult {
        if !isSurveyCompleted {
            return .setOneTime(index)
        } else {
            if userDataStore.shouldShowSurveyLater(surveyId: survey.id, userIdentifier: userID) {
                return .setOneTime(index)
            } else {
                return .continue
            }
        }
    }

    // MARK: - Survey Submission

    /// Submits a hero question response
    /// - Parameters:
    ///   - survey: The survey being answered
    ///   - heroQuestionResponse: The response to the hero question
    ///   - stopID: Optional stop ID if answered at a stop
    ///   - stopLocation: Optional stop coordinates
    /// - Returns: Submission response with update path for additional questions
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

        let surveyResponse = SurveyResponse(
            userIdentifier: userID,
            surveyId: survey.id,
            stopIdentifier: stopID,
            stopLatitude: stopLocation?.latitude,
            stopLongitude: stopLocation?.longitude,
            response: [heroQuestionResponse]
        )

        let response = try await apiService.submitSurveyResponse(surveyResponse)
        return response.entry
    }

    /// Submits additional questions for an existing survey response
    /// - Parameters:
    ///   - responseID: The ID from the initial submission
    ///   - additionalResponses: Responses to the remaining questions
    /// - Returns: Updated submission response
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

    // MARK: - Survey State Management

    /// Marks a survey as completed
    /// - Parameter survey: The survey that was completed
    public func markSurveyCompleted(_ survey: Survey) {
        let userID = userDataStore.surveyUserIdentifier
        userDataStore.markSurveyCompleted(surveyId: survey.id, userIdentifier: userID)
        updateVisibleSurveys()
    }

    /// Marks a survey to be shown later
    /// - Parameter survey: The survey to show later
    public func markSurveyForLater(_ survey: Survey) {
        let userID = userDataStore.surveyUserIdentifier
        userDataStore.markSurveyForLater(surveyId: survey.id, userIdentifier: userID)
        updateVisibleSurveys()
    }

    /// Marks a survey as dismissed (same as completed for dismissal purposes)
    /// - Parameter survey: The survey that was dismissed
    public func dismissSurvey(_ survey: Survey) {
        markSurveyCompleted(survey)
    }

    // MARK: - Helper Methods

    /// Creates a question response for a given question and answer
    /// - Parameters:
    ///   - question: The survey question
    ///   - answer: The answer provided by the user
    /// - Returns: Formatted survey question response
    public func createQuestionResponse(question: SurveyQuestion, answer: String) -> SurveyQuestionResponse {
        return SurveyQuestionResponse(
            questionId: question.id,
            questionType: question.content.typeString,
            questionLabel: question.content.displayText,
            answer: answer
        )
    }

    /// Formats multiple checkbox selections into a JSON array string
    /// - Parameter selections: Array of selected options
    /// - Returns: JSON-formatted string for checkbox responses
    public func formatCheckboxAnswer(_ selections: [String]) -> String {
        do {
            let jsonData = try JSONEncoder().encode(selections)
            return String(data: jsonData, encoding: .utf8) ?? "[]"
        } catch {
            return "[]"
        }
    }
}
