//
//  APIErrorMissingStopExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

/// Extended tests for `APIError.indicatesMissingStop` predicate boundaries,
/// status code matrix (400, 401, 403, 500, 503), and unknown content types.
@MainActor
@Suite(.serialized)
final class APIErrorMissingStopExtendedTests {

    private let url = URL(string: "https://api.example.com/api/where/stop.json")!

    private func httpResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "1.1", headerFields: nil)!
    }

    // MARK: - HTTP Status Code Matrix

    @Test func `Status 400 Bad Request does not indicate missing stop`() {
        let error = APIError.requestNotFound(httpResponse(statusCode: 400))
        #expect(!error.indicatesMissingStop)
    }

    @Test func `Status 401 Unauthorized does not indicate missing stop`() {
        let error = APIError.requestNotFound(httpResponse(statusCode: 401))
        #expect(!error.indicatesMissingStop)
    }

    @Test func `Status 403 Forbidden does not indicate missing stop`() {
        let error = APIError.requestNotFound(httpResponse(statusCode: 403))
        #expect(!error.indicatesMissingStop)
    }

    @Test func `Status 500 Server Error does not indicate missing stop`() {
        let error = APIError.requestNotFound(httpResponse(statusCode: 500))
        #expect(!error.indicatesMissingStop)
    }

    @Test func `Status 503 Service Unavailable does not indicate missing stop`() {
        let error = APIError.requestNotFound(httpResponse(statusCode: 503))
        #expect(!error.indicatesMissingStop)
    }

    // MARK: - Invalid Content Type Sentinel Variations

    @Test func `Empty string actualContentType does not indicate missing stop`() {
        let error = APIError.invalidContentType(originalError: nil, expectedContentType: "json", actualContentType: "")
        #expect(!error.indicatesMissingStop)
    }

    @Test func `Application JSON actualContentType does not indicate missing stop`() {
        let error = APIError.invalidContentType(originalError: nil, expectedContentType: "json", actualContentType: "application/json")
        #expect(!error.indicatesMissingStop)
    }

    @Test func `Non-matching expectedContentType does not indicate missing stop`() {
        let error = APIError.invalidContentType(originalError: nil, expectedContentType: "xml", actualContentType: "nothing")
        #expect(!error.indicatesMissingStop)
    }
}
