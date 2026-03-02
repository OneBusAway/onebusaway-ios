//
//  RESTAPIService+Surveys.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

extension RESTAPIService {

    // MARK: - Survey Endpoints

    /// Fetches all available surveys for a region and user
    /// - Parameter userID: The user's unique identifier
    /// - Returns: StudyResponse containing surveys and region info
    public nonisolated func getSurveys(userID: String) async throws -> RESTAPIResponse<StudyResponse> {
        guard let regionID = configuration.regionIdentifier else {
            throw APIError.noRegionSelected
        }

        guard let url = urlBuilder.getSurveys(userID: userID, regionID: regionID) else {
            throw APIError.surveyServiceNotConfigured
        }

        return try await getData(for: url, decodeRESTAPIResponseAs: StudyResponse.self, using: JSONDecoder.obacoServiceDecoder)
    }

    /// Submits a survey response to the server
    /// - Parameter surveySubmission: The survey submission to send
    /// - Returns: SurveySubmissionResponse with response ID and update path
    public nonisolated func submitSurveyResponse(_ surveySubmission: SurveySubmission) async throws -> RESTAPIResponse<SurveySubmissionResponse> {
        guard let url = urlBuilder.submitSurveyResponse() else {
            throw APIError.surveyServiceNotConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(surveySubmission)

        return try await performSurveyRequest(request: request)
    }

    /// Updates an existing survey response with additional answers
    /// - Parameters:
    ///   - responseID: The ID of the existing survey response
    ///   - additionalResponses: Additional question responses to add
    /// - Returns: Updated SurveySubmissionResponse
    public nonisolated func updateSurveyResponse(responseID: String, additionalResponses: [QuestionAnswerSubmission]) async throws -> RESTAPIResponse<SurveySubmissionResponse> {
        guard let url = urlBuilder.updateSurveyResponse(responseID: responseID) else {
            throw APIError.surveyServiceNotConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody = ["responses": additionalResponses]
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(requestBody)

        return try await performSurveyRequest(request: request)
    }

    // MARK: - Private Helper Methods

    private nonisolated func performSurveyRequest<T: Codable>(request: URLRequest) async throws -> RESTAPIResponse<T> {
        let (data, _) = try await self.data(for: request)
        return try JSONDecoder.obacoServiceDecoder.decode(RESTAPIResponse<T>.self, from: data)
    }
}
