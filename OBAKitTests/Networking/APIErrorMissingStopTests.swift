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

/// `APIError.indicatesMissingStop` is the single predicate the Bookmarks tab and the
/// Stop screen share (#1336). The negative cases matter as much as the positive ones:
/// each one is a `where` clause that, if dropped, silently widens the predicate and
/// starts offering riders the "delete this bookmark" path for a transient failure.
@MainActor
@Suite(.serialized)
final class APIErrorMissingStopTests {

    private let url = URL(string: "https://api.pugetsound.onebusaway.org/api/where/arrivals-and-departures-for-stop/1_75403.json")!

    private func response(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "2", headerFields: nil)!
    }

    @Test func `Literal 404 indicates a missing stop`() {
        #expect(APIError.requestNotFound(response(statusCode: 404)).indicatesMissingStop)
    }

    /// The boundary the whole design turns on. `APIService+GetData` throws
    /// `requestNotFound` for a blank HTTP 200 too, and that response carries a **200**.
    /// A live stop answers with a full 200, so a blank body is a transient blip.
    @Test func `Request not found carrying a 200 does not indicate a missing stop`() {
        #expect(!APIError.requestNotFound(response(statusCode: 200)).indicatesMissingStop)
    }

    @Test func `JSON null body indicates a missing stop`() {
        let error = APIError.invalidContentType(originalError: nil, expectedContentType: "json", actualContentType: "nothing")
        #expect(error.indicatesMissingStop)
    }

    @Test func `HTML instead of JSON does not indicate a missing stop`() {
        let error = APIError.invalidContentType(originalError: nil, expectedContentType: "json", actualContentType: "text/html")
        #expect(!error.indicatesMissingStop)
    }

    /// `APIService+GetData` throws exactly this when a non-JSON response carries no
    /// `Content-Type` header at all — a broken proxy, not a deleted stop.
    @Test func `Missing content type does not indicate a missing stop`() {
        let error = APIError.invalidContentType(originalError: nil, expectedContentType: "json", actualContentType: nil)
        #expect(!error.indicatesMissingStop)
    }

    /// The `"nothing"` sentinel is only meaningful for the JSON decode path. A protobuf
    /// endpoint returning it is a different failure and must not reach the stop UI.
    @Test func `Non JSON expectation does not indicate a missing stop`() {
        let error = APIError.invalidContentType(originalError: nil, expectedContentType: "protobuf", actualContentType: "nothing")
        #expect(!error.indicatesMissingStop)
    }

    @Test func `Network failure does not indicate a missing stop`() {
        #expect(!APIError.networkFailure(nil).indicatesMissingStop)
    }
}
