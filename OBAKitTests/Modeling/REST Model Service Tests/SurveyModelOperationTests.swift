//
//  SurveyModelOperationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class SurveyModelOperationTests: OBATestCase {

    private func makeSubmission(
        userIdentifier: String = "user-123",
        surveyId: Int = 1,
        stopIdentifier: String? = "stop-456",
        stopLongitude: Double? = -122.33,
        stopLatitude: Double? = 47.60,
        responses: [QuestionAnswerSubmission] = [
            .init(questionId: 10, questionType: "text", questionLabel: "Rate", answer: "Good")
        ]
    ) -> SurveySubmission {
        SurveySubmission(
            userIdentifier: userIdentifier,
            surveyId: surveyId,
            stopIdentifier: stopIdentifier,
            stopLongitude: stopLongitude,
            stopLatitude: stopLatitude,
            responses: responses
        )
    }

    // MARK: - GET Surveys Validation & Headers

    @Test func `getSurveys sends expected query items and decodes payload`() async throws {
        let dataLoader = (restService.dataLoader as! MockDataLoader)
        let expectedURL = "https://onebusaway.co/api/v1/regions/\(pugetSoundRegionIdentifier)/surveys.json?user_id=\(uuid)&key=\(apiKey)"
        dataLoader.mock(
            URLString: expectedURL,
            with: Fixtures.loadData(file: "surveys_always_visible_one_time.json")
        )

        let response = try await restService.getSurveys(userID: uuid)
        #expect(response.region.name == "Puget Sound")
        #expect(response.region.id == 1)
        #expect(!response.surveys.isEmpty)

        let requestURL = try #require(dataLoader.recordedRequestURLs.first)
        let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false)
        #expect(components?.path == "/api/v1/regions/1/surveys.json")
        #expect(components?.queryItems?.contains(URLQueryItem(name: "user_id", value: uuid)) == true)
        #expect(components?.queryItems?.contains(URLQueryItem(name: "key", value: apiKey)) == true)
    }

    @Test func `getSurveys throws noRegionSelected when regionIdentifier is nil`() async {
        let configWithoutRegion = APIServiceConfiguration(
            baseURL: baseURL,
            apiKey: apiKey,
            uuid: uuid,
            appVersion: appVersion,
            regionIdentifier: nil,
            surveyBaseURL: surveyBaseURL
        )
        let serviceWithoutRegion = RESTAPIService(configWithoutRegion, dataLoader: MockDataLoader(testName: name))

        await #expect {
            try await serviceWithoutRegion.getSurveys(userID: uuid)
        } throws: { error in
            guard let apiError = error as? APIError, case .noRegionSelected = apiError else { return false }
            return true
        }
    }

    @Test func `getSurveys throws surveyServiceNotConfigured when surveyBaseURL is nil`() async {
        let configWithoutSurveyURL = APIServiceConfiguration(
            baseURL: baseURL,
            apiKey: apiKey,
            uuid: uuid,
            appVersion: appVersion,
            regionIdentifier: pugetSoundRegionIdentifier,
            surveyBaseURL: nil
        )
        let serviceWithoutSurvey = RESTAPIService(configWithoutSurveyURL, dataLoader: MockDataLoader(testName: name))

        await #expect {
            try await serviceWithoutSurvey.getSurveys(userID: uuid)
        } throws: { error in
            guard let apiError = error as? APIError, case .surveyServiceNotConfigured = apiError else { return false }
            return true
        }
    }

    // MARK: - POST Survey Response Validation & Headers

    @Test func `submitSurveyResponse sends POST with JSON Content-Type and parses response`() async throws {
        let dataLoader = (restService.dataLoader as! MockDataLoader)
        let successData = Fixtures.loadData(file: "survey_submission_response.json")

        let capturedMethod = SendableBox<String?>(nil)
        let capturedContentType = SendableBox<String?>(nil)
        let capturedBodyData = SendableBox<Data?>(nil)

        dataLoader.mock(data: successData) { request in
            guard request.url?.path == "/api/v1/survey_responses/" else { return false }
            capturedMethod.value = request.httpMethod
            capturedContentType.value = request.value(forHTTPHeaderField: "Content-Type")
            capturedBodyData.value = request.httpBody
            return true
        }

        let submission = makeSubmission()
        let result = try await restService.submitSurveyResponse(submission)

        #expect(capturedMethod.value == "POST")
        #expect(capturedContentType.value == "application/json")
        #expect(result.id == "808d3a515daa39f4c15a")
        #expect(result.updatePath == "/api/v1/survey_responses/808d3a515daa39f4c15a")
        #expect(result.userIdentifier == "b94e83ae-5337-42f4-bec7-2736e7929dcb")

        // Verify request payload contents on wire
        let bodyData = try #require(capturedBodyData.value)
        let json = try #require(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        #expect(json["user_identifier"] as? String == "user-123")
        #expect(json["survey_id"] as? Int == 1)
        #expect(json["stop_identifier"] as? String == "stop-456")
        #expect(json["responses"] is String)
    }

    @Test func `submitSurveyResponse throws surveyServiceNotConfigured when surveyBaseURL is nil`() async {
        let configWithoutSurveyURL = APIServiceConfiguration(
            baseURL: baseURL,
            apiKey: apiKey,
            uuid: uuid,
            appVersion: appVersion,
            regionIdentifier: pugetSoundRegionIdentifier,
            surveyBaseURL: nil
        )
        let serviceWithoutSurvey = RESTAPIService(configWithoutSurveyURL, dataLoader: MockDataLoader(testName: name))

        await #expect {
            try await serviceWithoutSurvey.submitSurveyResponse(makeSubmission())
        } throws: { error in
            guard let apiError = error as? APIError, case .surveyServiceNotConfigured = apiError else { return false }
            return true
        }
    }

    // MARK: - PUT Survey Response Update Validation & Headers

    @Test func `updateSurveyResponse sends PUT with JSON body and parses response`() async throws {
        let dataLoader = (restService.dataLoader as! MockDataLoader)
        let successData = Fixtures.loadData(file: "survey_submission_response.json")

        let capturedMethod = SendableBox<String?>(nil)
        let capturedContentType = SendableBox<String?>(nil)
        let capturedBodyData = SendableBox<Data?>(nil)
        let capturedPath = SendableBox<String?>(nil)

        dataLoader.mock(data: successData) { request in
            guard let path = request.url?.path, path.hasPrefix("/api/v1/survey_responses/") else { return false }
            capturedMethod.value = request.httpMethod
            capturedContentType.value = request.value(forHTTPHeaderField: "Content-Type")
            capturedBodyData.value = request.httpBody
            capturedPath.value = path
            return true
        }

        let additionalAnswers: [QuestionAnswerSubmission] = [
            .init(questionId: 15, questionType: "radio", questionLabel: "Option", answer: "A"),
            .init(questionId: 16, questionType: "text", questionLabel: "Comment", answer: "None")
        ]

        let result = try await restService.updateSurveyResponse(
            responseID: "resp_update_789",
            additionalResponses: additionalAnswers
        )

        #expect(capturedMethod.value == "PUT")
        #expect(capturedContentType.value == "application/json")
        #expect(capturedPath.value == "/api/v1/survey_responses/resp_update_789")
        #expect(result.id == "808d3a515daa39f4c15a")

        let bodyData = try #require(capturedBodyData.value)
        let bodyJson = try #require(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let responsesString = try #require(bodyJson["responses"] as? String)
        let parsed = try #require(try JSONSerialization.jsonObject(with: Data(responsesString.utf8)) as? [[String: Any]])
        #expect(parsed.count == 2)
        #expect(parsed[0]["question_id"] as? Int == 15)
        #expect(parsed[0]["answer"] as? String == "A")
    }

    @Test func `updateSurveyResponse escapes responseID in URL path`() async throws {
        let dataLoader = (restService.dataLoader as! MockDataLoader)
        let successData = Fixtures.loadData(file: "survey_submission_response.json")

        let capturedPath = SendableBox<String?>(nil)
        dataLoader.mock(data: successData) { request in
            capturedPath.value = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedPath }
            return true
        }

        _ = try await restService.updateSurveyResponse(
            responseID: "resp/with slash",
            additionalResponses: [
                .init(questionId: 1, questionType: "text", questionLabel: "L", answer: "Ans")
            ]
        )

        #expect(capturedPath.value == "/api/v1/survey_responses/resp%2Fwith%20slash")
    }

    @Test func `updateSurveyResponse throws surveyServiceNotConfigured when surveyBaseURL is nil`() async {
        let configWithoutSurveyURL = APIServiceConfiguration(
            baseURL: baseURL,
            apiKey: apiKey,
            uuid: uuid,
            appVersion: appVersion,
            regionIdentifier: pugetSoundRegionIdentifier,
            surveyBaseURL: nil
        )
        let serviceWithoutSurvey = RESTAPIService(configWithoutSurveyURL, dataLoader: MockDataLoader(testName: name))

        await #expect {
            try await serviceWithoutSurvey.updateSurveyResponse(
                responseID: "any_id",
                additionalResponses: []
            )
        } throws: { error in
            guard let apiError = error as? APIError, case .surveyServiceNotConfigured = apiError else { return false }
            return true
        }
    }

    // MARK: - Server Error Status Code Handling

    @Test func `submitSurveyResponse handles 404 response as requestNotFound`() async throws {
        let dataLoader = (restService.dataLoader as! MockDataLoader)
        let urlResponse = HTTPURLResponse(
            url: URL(string: "https://onebusaway.co/api/v1/survey_responses/")!,
            statusCode: 404,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let mockResponse = MockDataResponse(
            data: Data("{\"message\": \"Not Found\"}".utf8),
            urlResponse: urlResponse,
            error: nil
        ) { $0.url?.path == "/api/v1/survey_responses/" }
        dataLoader.mock(response: mockResponse)

        await #expect {
            try await restService.submitSurveyResponse(makeSubmission())
        } throws: { error in
            guard let apiError = error as? APIError, case .requestNotFound(let response) = apiError else { return false }
            return response.statusCode == 404
        }
    }

    @Test func `updateSurveyResponse handles 500 internal server error`() async throws {
        let dataLoader = (restService.dataLoader as! MockDataLoader)
        let urlResponse = HTTPURLResponse(
            url: URL(string: "https://onebusaway.co/api/v1/survey_responses/err_500")!,
            statusCode: 500,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/html"]
        )!
        let mockResponse = MockDataResponse(
            data: Data("500 Server Error".utf8),
            urlResponse: urlResponse,
            error: nil
        ) { $0.url?.path.contains("err_500") == true }
        dataLoader.mock(response: mockResponse)

        await #expect {
            try await restService.updateSurveyResponse(
                responseID: "err_500",
                additionalResponses: []
            )
        } throws: { error in
            guard let apiError = error as? APIError, case .requestFailure(let response) = apiError else { return false }
            return response.statusCode == 500
        }
    }
}
