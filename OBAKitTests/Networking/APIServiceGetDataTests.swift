//
//  APIServiceGetDataTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import os.log
import Testing
@testable import OBAKit
@testable import OBAKitCore

// MARK: - Test API Service (shared with APIServiceSendDataTests pattern)

private nonisolated final class GetDataTestAPIService: APIService {
    let configuration: APIServiceConfiguration
    let dataLoader: URLDataLoader
    let retryPolicy: RetryPolicy = .disabled
    let logger = os.Logger(subsystem: "org.onebusaway.iphone", category: "GetDataTestAPIService")

    init(_ configuration: APIServiceConfiguration, dataLoader: URLDataLoader) {
        self.configuration = configuration
        self.dataLoader = dataLoader
    }
}

// MARK: - Tests

@Suite(.serialized)
final class APIServiceGetDataTests: OBATestCase {

    private var dataLoader: MockDataLoader!
    private var service: GetDataTestAPIService!
    private let testURL = URL(string: "https://api.example.com/api/where/stop/1_75403.json")!

    override init() async throws {
        try await super.init()

        dataLoader = MockDataLoader(testName: name)
        let config = APIServiceConfiguration(
            baseURL: baseURL,
            apiKey: apiKey,
            uuid: uuid,
            appVersion: appVersion,
            regionIdentifier: pugetSoundRegionIdentifier,
            surveyBaseURL: surveyBaseURL
        )
        service = GetDataTestAPIService(config, dataLoader: dataLoader)
    }

    // MARK: - httpMethod is explicitly "GET"

    @Test func `getData sets httpMethod to GET`() async throws {
        let body = Data(#"{"entry":{}}"#.utf8)
        dataLoader.mock(data: body) { $0.url == self.testURL }

        _ = try await service.getData(for: testURL)

        let recorded = dataLoader.recordedRequests.first
        #expect(recorded?.httpMethod == "GET")
    }

    // MARK: - Empty-body 200 → requestNotFound

    @Test func `getData throws requestNotFound for 200 with zero content length`() async throws {
        // Simulate the REST API returning 200 with an empty body (a bogus stop ID, for instance).
        let response = dataLoader.buildURLResponse(
            URL: testURL,
            statusCode: 200,
            contentLength: 0,
            contentType: "application/json"
        )
        let mockResponse = MockDataResponse(
            data: Data(),
            urlResponse: response,
            error: nil
        ) { $0.url == self.testURL }
        dataLoader.mock(response: mockResponse)

        await #expect(throws: APIError.self) {
            _ = try await service.getData(for: testURL)
        }

        // Verify it's specifically requestNotFound.
        do {
            _ = try await service.getData(for: testURL)
            Issue.record("Expected APIError.requestNotFound to be thrown")
        } catch let error as APIError {
            guard case .requestNotFound = error else {
                Issue.record("Expected .requestNotFound, got \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - Empty data body → noResponseBody

    @Test func `getData throws noResponseBody when server returns empty data`() async throws {
        // Server returns 200 with Content-Length > 0 but actual data is empty
        // (content-length unknown / -1, so the first heuristic doesn't fire,
        // but the data is still empty).
        let response = dataLoader.buildURLResponse(
            URL: testURL,
            statusCode: 200,
            contentType: "application/json"
            // no contentLength → expectedContentLength == NSURLResponseUnknownLength
        )
        let mockResponse = MockDataResponse(
            data: Data(),
            urlResponse: response,
            error: nil
        ) { $0.url == self.testURL }
        dataLoader.mock(response: mockResponse)

        do {
            _ = try await service.getData(for: testURL)
            Issue.record("Expected APIError.noResponseBody to be thrown")
        } catch let error as APIError {
            guard case .noResponseBody = error else {
                Issue.record("Expected .noResponseBody, got \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - Normal 200 response succeeds

    @Test func `getData succeeds with valid JSON response`() async throws {
        let jsonData = Data(#"{"entry":{"stopId":"1_75403"}}"#.utf8)
        dataLoader.mock(data: jsonData) { $0.url == self.testURL }

        let (data, response) = try await service.getData(for: testURL)

        #expect(!data.isEmpty)
        #expect(response.statusCode == 200)
    }

    // MARK: - 404 response throws requestNotFound

    @Test func `getData throws requestNotFound for 404`() async throws {
        let response = dataLoader.buildURLResponse(
            URL: testURL,
            statusCode: 404,
            contentLength: 0,
            contentType: "application/json"
        )
        let mockResponse = MockDataResponse(
            data: Data(),
            urlResponse: response,
            error: nil
        ) { $0.url == self.testURL }
        dataLoader.mock(response: mockResponse)

        do {
            _ = try await service.getData(for: testURL)
            Issue.record("Expected APIError.requestNotFound to be thrown")
        } catch let error as APIError {
            guard case .requestNotFound = error else {
                Issue.record("Expected .requestNotFound, got \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - Accept-Encoding and Accept-Language headers

    @Test func `getData sets Accept-Encoding and Accept-Language headers`() async throws {
        let body = Data(#"{"ok":true}"#.utf8)
        dataLoader.mock(data: body) { $0.url == self.testURL }

        _ = try await service.getData(for: testURL)

        let recorded = dataLoader.recordedRequests.first
        #expect(recorded?.value(forHTTPHeaderField: "Accept-Encoding") == "gzip")
        #expect(recorded?.value(forHTTPHeaderField: "Accept-Language") == "en-US")
    }
}
