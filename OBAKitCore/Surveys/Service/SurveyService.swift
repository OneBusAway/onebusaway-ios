//
//  SurveyService.swift
//  OBAKitCore
//
//  Created by Mohamed Sliem on 28/11/2025.
//

import Foundation

public final class SurveyService: SurveyServiceProtocol, ObservableObject {

    /// All surveys fetched from the backend.
    public private(set) var surveys: [Survey] = []

    /// Networking layer responsible for API operations related to surveys.
    private let apiService: SurveyAPIService?

    /// Local storage for survey preferences and persisted metadata.
    private let surveyStore: SurveyPreferencesStore

    /// Creates a survey service instance.
    ///
    /// - Parameters:
    ///   - apiService: API layer used to fetch and submit surveys.
    ///   - surveyStore: Storage object used for saving user-specific survey metadata.
    public init(apiService: SurveyAPIService?, surveyStore: SurveyPreferencesStore) {
        self.apiService = apiService
        self.surveyStore = surveyStore
    }

    /// Fetches all available surveys from the backend,
    /// stores them locally, and refreshes the visible surveys list.
    ///
    /// Any error during fetch is published through `error`.
    @MainActor
    public func fetchSurveys() async throws {

        guard let apiService else {
            Logger.error("Survey API service is nil.")
            throw SurveyError.serviceUnavailable
        }

        do {
            let studyResponse = try await apiService.getSurveys()
            self.surveys = studyResponse.surveys
        } catch {
            throw error
        }
    }

    /// Submits a single survey response to the backend.
    ///
    /// - Parameters:
    ///   - surveyId: ID of the survey being answered.
    ///   - stopIdentifier: Optional stop ID where the survey was shown.
    ///   - stopLongitude: Optional longitude of the stop.
    ///   - stopLatitude: Optional latitude of the stop.
    ///   - response: A single question-answer submission model.
    ///
    /// Upon successful submission, the server response is saved in `UserDefaults`.
    @MainActor
    public func submitSurveyResponse(
        surveyId: Int,
        stopIdentifier: String? = nil,
        stopLongitude: Double? = nil,
        stopLatitude: Double? = nil,
        _ response: QuestionAnswerSubmission
    ) async throws {

        let userId = surveyStore.userSurveyId

        // Build submission model with a single response.
        let responseModel = SurveySubmission(
            userIdentifier: userId,
            surveyId: surveyId,
            stopIdentifier: stopIdentifier,
            stopLongitude: stopLongitude,
            stopLatitude: stopLatitude,
            responses: [response]
        )

        guard let apiService else {
            Logger.error("Survey API service is nil.")
            throw SurveyError.serviceUnavailable
        }

        do {
            let submissionResponse = try await apiService.submitSurveyResponse(surveyResponse: responseModel)
            surveyStore.setSurveyResponse(submissionResponse)
        } catch {
            throw error
        }
    }

    /// Updates an already submitted survey response by PATCHing the new data.
    ///
    /// - Parameters:
    ///   - surveyId: ID of the survey being updated.
    ///   - stopIdentifier: Optional stop ID at the update moment.
    ///   - stopLongitude: Optional longitude of the stop.
    ///   - stopLatitude: Optional latitude of the stop.
    ///   - responses: List of updated survey question responses.
    ///
    /// Uses the previously stored response path ID.
    @MainActor
    public func updateSurveyResponses(
        surveyId: Int,
        stopIdentifier: String? = nil,
        stopLongitude: Double? = nil,
        stopLatitude: Double? = nil,
        _ responses: [QuestionAnswerSubmission]
    ) async throws {

        let userId = surveyStore.userSurveyId

        /// Retrieve the path ID used for updating survey responses.
        guard let surveyResponseId = surveyStore.getSurveyResponse()?.surveyPathId() else {
            Logger.error("Missing survey update path from Survey Store for survey id: \(surveyId)")
            throw SurveyError.missingUpdatePath
        }

        let responsesModel = SurveySubmission(
            userIdentifier: userId,
            surveyId: surveyId,
            stopIdentifier: stopIdentifier,
            stopLongitude: stopLongitude,
            stopLatitude: stopLatitude,
            responses: responses
        )

        guard let apiService else {
            Logger.error("Survey API service is nil.")
            throw SurveyError.serviceUnavailable
        }

        do {
            try await apiService.updateSurveyResponse(
                surveyResponseId: surveyResponseId,
                surveyResponses: responsesModel
            )
        } catch {
            throw error
        }
    }

}
