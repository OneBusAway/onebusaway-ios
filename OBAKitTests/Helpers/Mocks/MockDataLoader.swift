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
    var mockResponses = [MockDataResponse]()

    let testName: String

    init(testName: String) {
        self.testName = testName
    }

    func dataTask(with request: URLRequest, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        guard let response = matchResponse(to: request) else {
            fatalError("\(testName): Missing response to URL: \(request.url!)")
        }

        return MockTask(mockResponse: response, closure: completionHandler)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
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
        for r in mockResponses {
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
        mockResponses.append(response)
    }

    func removeMappedResponses() {
        mockResponses.removeAll()
    }

    // MARK: - URL Response

    func buildURLResponse(URL: URL, statusCode: Int) -> HTTPURLResponse {
        return HTTPURLResponse(url: URL, statusCode: statusCode, httpVersion: "2", headerFields: ["Content-Type": "application/json"])!
    }

    // MARK: - Description

    override var debugDescription: String {
        var descriptionBuilder = DebugDescriptionBuilder(baseDescription: super.debugDescription)
        descriptionBuilder.add(key: "mockResponses", value: mockResponses)
        return descriptionBuilder.description
    }
}
