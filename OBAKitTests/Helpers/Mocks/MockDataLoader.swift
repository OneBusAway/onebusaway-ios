//
//  MockDataLoader.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

typealias MockDataLoaderMatcher = (URLRequest) -> Bool

struct MockDataResponse {
    let data: Data?
    let urlResponse: URLResponse?
    let error: Error?
    let matcher: MockDataLoaderMatcher
}

class MockTask: URLSessionDataTask {
    override var progress: Progress {
        return Progress()
    }

    private var closure: (Data?, URLResponse?, Error?) -> Void
    private let mockResponse: MockDataResponse

    init(mockResponse: MockDataResponse, closure: @escaping (Data?, URLResponse?, Error?) -> Void) {
        self.mockResponse = mockResponse
        self.closure = closure
    }

    // We override the 'resume' method and simply call our closure
    // instead of actually resuming any task.
    override func resume() {
        closure(mockResponse.data, mockResponse.urlResponse, mockResponse.error)
    }

    override func cancel() {
        // nop
    }
}

class MockDataLoader: NSObject, URLDataLoader {
    /// Guarded by `mockResponsesLock`: tests mutate the response table from the main
    /// thread while `Application` background tasks (regions refresh, agency alerts)
    /// concurrently match requests against it.
    private var mockResponses = [MockDataResponse]()
    private let mockResponsesLock = NSLock()

    /// URLs of every request seen by `dataTask(with:)` or `data(for:)`.
    /// Lets tests assert that no network call was made (e.g. when a fetch should be
    /// short-circuited by cached/preloaded data). Reads/writes go through
    /// `recordedRequestURLsLock` because real callers fan out across multiple
    /// concurrent tasks (e.g. `AgencyAlertsStore.update()`'s alerts task group).
    private var _recordedRequestURLs = [URL]()
    private let recordedRequestURLsLock = NSLock()
    var recordedRequestURLs: [URL] {
        recordedRequestURLsLock.withLock { _recordedRequestURLs }
    }
    private func recordRequest(_ url: URL?) {
        guard let url else { return }
        recordedRequestURLsLock.withLock { _recordedRequestURLs.append(url) }
    }

    /// Clears recorded request URLs. Useful in tests that need to ignore the
    /// requests made during `Application` startup and only assert about calls
    /// that happen after a specific action.
    func resetRecordedRequestURLs() {
        recordedRequestURLsLock.withLock { _recordedRequestURLs.removeAll() }
    }

    let testName: String

    init(testName: String) {
        self.testName = testName
    }

    func dataTask(with request: URLRequest, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        recordRequest(request.url)
        guard let response = matchResponse(to: request) else {
            fatalError("\(testName): Missing response to URL: \(request.url!)")
        }

        return MockTask(mockResponse: response, closure: completionHandler)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        recordRequest(request.url)
        guard let response = matchResponse(to: request) else {
            fatalError("\(testName): Missing response to URL: \(request.url!)")
        }

        if let error = response.error {
            throw error
        }

        guard let data = response.data else {
            fatalError("\(testName): Missing data to URL: \(request.url!))")
        }

        guard let urlResponse = response.urlResponse else {
            fatalError("\(testName): Missing urlResponse to URL: \(request.url!))")
        }

        return (data, urlResponse)
    }

    // MARK: - Response Mapping

    func matchResponse(to request: URLRequest) -> MockDataResponse? {
        let responses = mockResponsesLock.withLock { mockResponses }
        for r in responses {
            if r.matcher(request) {
                return r
            }
        }

        return nil
    }

    func mock(data: Data, matcher: @escaping MockDataLoaderMatcher) {
        let urlResponse = buildURLResponse(URL: URL(string: "https://mockdataloader.example.com")!, statusCode: 200)
        let mockResponse = MockDataResponse(data: data, urlResponse: urlResponse, error: nil, matcher: matcher)
        mock(response: mockResponse)
    }

    func mock(URLString: String, with data: Data) {
        mock(url: URL(string: URLString)!, with: data)
    }

    func mock(url: URL, with data: Data) {
        let urlResponse = buildURLResponse(URL: url, statusCode: 200)
        let mockResponse = MockDataResponse(data: data, urlResponse: urlResponse, error: nil) {
            let requestURL = $0.url!
            return requestURL.host == url.host && requestURL.path == url.path
        }
        mock(response: mockResponse)
    }

    func mock(response: MockDataResponse) {
        mockResponsesLock.withLock { mockResponses.append(response) }
    }

    func removeMappedResponses() {
        mockResponsesLock.withLock { mockResponses.removeAll() }
    }

    /// Atomically replaces every mocked response with the ones registered in `register`.
    ///
    /// Use this instead of `removeMappedResponses()` + re-mocking when the test's
    /// `Application` may have background requests in flight: a separate clear-then-mock
    /// sequence leaves a window with no registered responses, and any request landing
    /// in that window hits `fatalError` and takes down the whole suite.
    func replaceMappedResponses(_ register: (MockDataLoader) -> Void) {
        let staging = MockDataLoader(testName: testName)
        register(staging)
        let newResponses = staging.mockResponsesLock.withLock { staging.mockResponses }
        mockResponsesLock.withLock { mockResponses = newResponses }
    }

    // MARK: - URL Response

    func buildURLResponse(URL: URL, statusCode: Int) -> HTTPURLResponse {
        return HTTPURLResponse(url: URL, statusCode: statusCode, httpVersion: "2", headerFields: ["Content-Type": "application/json"])!
    }

    // MARK: - Description

    override var debugDescription: String {
        var descriptionBuilder = DebugDescriptionBuilder(baseDescription: super.debugDescription)
        descriptionBuilder.add(key: "mockResponses", value: mockResponsesLock.withLock { mockResponses })
        return descriptionBuilder.description
    }
}
