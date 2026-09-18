
//
//  APIErrorMissingStopTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

@Suite(.serialized)
final class APIErrorMissingStopTests {
    @Test func testIndicatesMissingStopFor404() {
        let response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 404, httpVersion: nil, headerFields: nil)!
        let error = APIError.requestNotFound(response)
        #expect(error.indicatesMissingStop)
    }

    @Test func testIndicatesMissingStopForNullBody() {
        let error = APIError.invalidContentType(originalError: nil, expectedContentType: "json", actualContentType: "nothing")
        #expect(error.indicatesMissingStop)
    }

    @Test func testDoesNotIndicateMissingStopForOtherErrors() {
        let response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 500, httpVersion: nil, headerFields: nil)!
        let error1 = APIError.requestFailure(response)
        #expect(!error1.indicatesMissingStop)

        let error2 = APIError.invalidContentType(originalError: nil, expectedContentType: "json", actualContentType: "xml")
        #expect(!error2.indicatesMissingStop)

        let error3 = APIError.noResponseBody
        #expect(!error3.indicatesMissingStop)
    }
}

