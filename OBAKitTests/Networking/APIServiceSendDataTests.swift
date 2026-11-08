//
//  APIServiceSendDataTests.swift
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

private struct MockRequestPayload: Codable, Equatable {
    let name: String
    let amount: Int
}

private struct MockResponsePayload: Codable, Equatable {
    let id: String
    let success: Bool
}

private final class TestAPIService: APIService {
    let configuration: APIServiceConfiguration
    let dataLoader: URLDataLoader
    let logger = os.Logger(subsystem: "org.onebusaway.iphone", category: "TestAPIService")

    init(_ configuration: APIServiceConfiguration, dataLoader: URLDataLoader) {
        self.configuration = configuration
        self.dataLoader = dataLoader
    }
}

@Suite(.serialized)
final class APIServiceSendDataTests: OBATestCase {

    private var dataLoader: MockDataLoader!
    private var service: TestAPIService!
    private let endpointURL = URL(string: "https://www.example.com/api/test_action")!

    override init() async throws {
        try await super.init()

        dataLoader = try #require(restService.dataLoader as? MockDataLoader)
        service = TestAPIService(restService.configuration, dataLoader: dataLoader)
    }

    // MARK: - Successful POST & PUT

    @Test func `postData sends JSON body with POST method and decodes response`() async throws {
        let requestPayload = MockRequestPayload(name: "BusPass", amount: 250)
        let responsePayload = MockResponsePayload(id: "tx_123", success: true)
        let responseData = try JSONEncoder().encode(responsePayload)

        dataLoader.mock(data: responseData) { request in
            guard let url = request.url, url == self.endpointURL else { return false }
            guard request.httpMethod == "POST" else { return false }
            guard request.value(forHTTPHeaderField: "Content-Type") == "application/json" else { return false }
            guard request.value(forHTTPHeaderField: "Accept-Language") == "en-US" else { return false }

            if let body = request.httpBody,
               let decoded = try? JSONDecoder().decode(MockRequestPayload.self, from: body) {
                return decoded == requestPayload
            }
            return false
        }

        let result: MockResponsePayload = try await service.postData(url: endpointURL, data: requestPayload)
        #expect(result == responsePayload)
    }

    @Test func `updateData sends JSON body with PUT method and decodes response`() async throws {
        let requestPayload = MockRequestPayload(name: "MonthlyPass", amount: 5000)
        let responsePayload = MockResponsePayload(id: "tx_456", success: true)
        let responseData = try JSONEncoder().encode(responsePayload)

        dataLoader.mock(data: responseData) { request in
            guard let url = request.url, url == self.endpointURL else { return false }
            guard request.httpMethod == "PUT" else { return false }
            guard request.value(forHTTPHeaderField: "Content-Type") == "application/json" else { return false }

            if let body = request.httpBody,
               let decoded = try? JSONDecoder().decode(MockRequestPayload.self, from: body) {
                return decoded == requestPayload
            }
            return false
        }

        let result: MockResponsePayload = try await service.updateData(url: endpointURL, data: requestPayload)
        #expect(result == responsePayload)
    }

    // MARK: - Error Handling

    @Test func `HTTP 404 response throws requestNotFound error`() async throws {
        let requestPayload = MockRequestPayload(name: "Item", amount: 10)
        let response = HTTPURLResponse(url: endpointURL, statusCode: 404, httpVersion: "2.0", headerFields: nil)!
        let mockResponse = MockDataResponse(data: Data(), urlResponse: response, error: nil) { $0.url == self.endpointURL }
        dataLoader.mock(mockResponse: mockResponse)

        do {
            let _: MockResponsePayload = try await service.postData(url: endpointURL, data: requestPayload)
            Issue.record("Expected APIError.requestNotFound to be thrown")
        } catch let error as APIError {
            switch error {
            case .requestNotFound:
                #expect(true)
            default:
                Issue.record("Expected .requestNotFound, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func `HTTP 500 response throws requestFailure error`() async throws {
        let requestPayload = MockRequestPayload(name: "Item", amount: 10)
        let response = HTTPURLResponse(url: endpointURL, statusCode: 500, httpVersion: "2.0", headerFields: nil)!
        let mockResponse = MockDataResponse(data: Data("Server Error".utf8), urlResponse: response, error: nil) { $0.url == self.endpointURL }
        dataLoader.mock(mockResponse: mockResponse)

        do {
            let _: MockResponsePayload = try await service.postData(url: endpointURL, data: requestPayload)
            Issue.record("Expected APIError.requestFailure to be thrown")
        } catch let error as APIError {
            switch error {
            case .requestFailure:
                #expect(true)
            default:
                Issue.record("Expected .requestFailure, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func `Captive portal network error is translated to APIError captivePortal`() async throws {
        let requestPayload = MockRequestPayload(name: "Item", amount: 10)
        let captiveError = NSError(domain: NSCocoaErrorDomain, code: 3840, userInfo: nil)
        let mockResponse = MockDataResponse(data: Data(), urlResponse: nil, error: captiveError) { $0.url == self.endpointURL }
        dataLoader.mock(mockResponse: mockResponse)

        do {
            let _: MockResponsePayload = try await service.postData(url: endpointURL, data: requestPayload)
            Issue.record("Expected APIError.captivePortal to be thrown")
        } catch let error as APIError {
            switch error {
            case .captivePortal:
                #expect(true)
            default:
                Issue.record("Expected .captivePortal, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}
