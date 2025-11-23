//
//  SurveyAPIService.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import os.log

public actor SurveyAPIService: @preconcurrency APIService {

    public nonisolated let configuration: APIServiceConfiguration

    public nonisolated let dataLoader: any URLDataLoader

    public let logger =  os.Logger(subsystem: "org.onebusaway.iphone", category: "SurveyAPIService")

    nonisolated let urlBuilder: RESTAPIURLBuilder
    nonisolated let decoder: JSONDecoder

    private nonisolated var regionIdentifier: Int {
        guard let regionID = configuration.regionIdentifier else {
            preconditionFailure("Configuration must have a region identifier.")
        }
        return regionID
    }

    public init(_ configuration: APIServiceConfiguration, dataLoader: URLDataLoader = URLSession.shared) {
        self.configuration = configuration
        self.dataLoader = dataLoader

        /// sidecarURL will be passed as baseURL
        self.urlBuilder = RESTAPIURLBuilder(baseURL: configuration.baseURL, defaultQueryItems: configuration.defaultQueryItems)

        // contains logic of decoding the date format correctly in survey response
        self.decoder = JSONDecoder.obacoServiceDecoder
    }

    /// Fetches all surveys for the configured region and user.
    /// - Returns: A `StudyResponse` containing the list of surveys.
    /// - Throws: An `APIError` if the network request or decoding fails.
    public nonisolated func getSurveys() async throws -> StudyResponse {
        let url = urlBuilder.getSurveys(
            regionId: regionIdentifier,
            userIdentifier: configuration.uuid
        )
        return try await getData(for: url, decodeAs: StudyResponse.self, using: decoder)
    }

    /// Submits a new survey response.
    /// - Parameter surveyResponse: The survey response to submit.
    /// - Returns: The server response containing the submitted survey info.
    /// - Throws: An `APIError` if the network request or decoding fails.
    public nonisolated func submitSurveyResponse(
        surveyResponse: SurveySubmission
    ) async throws -> SurveySubmissionResponse {
        let url = urlBuilder.submitSurveyResponse()
        return try await postData(url: url, data: surveyResponse)
    }

    /// Updates an existing survey response.
    /// - Parameters:
    ///   - surveyResponseId: The ID of the survey response to update.
    ///   - surveyResponses: The updated survey response data.
    /// - Returns: The server response containing the updated survey info.
    /// - Throws: An `APIError` if the network request or decoding fails.
    public nonisolated func updateSurveyResponse(
        surveyResponseId: String,
        surveyResponses: SurveySubmission
    ) async throws -> SurveySubmissionResponse {
        let url = urlBuilder.updateSurveyResponse(surveyResponseId: surveyResponseId)
        return try await updateData(url: url, data: surveyResponses)
    }

}
