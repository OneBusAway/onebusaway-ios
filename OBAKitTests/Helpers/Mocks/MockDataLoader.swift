//
//  MockDataLoader.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 5/1/20.
//

import Foundation
import OBAKitCore

struct MockDataResponse {
    let data: Data?
    let urlResponse: URLResponse?
    let error: Error?
}

class MockDataLoader: NSObject, URLDataLoader {
    var urlResponseMap = [URL: MockDataResponse]()

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func dataTask(with request: URLRequest, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        guard let url = request.url, let response = urlResponseMap[url] else {
            fatalError()
        }

        completionHandler(response.data, response.urlResponse, response.error)

        return URLSessionDataTask()
    }

    // MARK: - Response Mapping

    func mock(path: String, with data: Data) {
        let response = buildURLResponse(path: path, statusCode: 200)
        let mockResponse = MockDataResponse(data: data, urlResponse: response, error: nil)
        mock(path: "/api/v1/regions/1/weather.json", response: mockResponse)
    }

    func mock(path: String, response: MockDataResponse) {
        let url = buildURL(path: path)
        urlResponseMap[url] = response
    }

    func removeMappedResponses() {
        urlResponseMap.removeAll()
    }

    // MARK: - URL Response

    func buildURLResponse(path: String, statusCode: Int) -> HTTPURLResponse {
        return HTTPURLResponse(url: buildURL(path: path), statusCode: 200, httpVersion: "2", headerFields: nil)!
    }

    // MARK: - URLs

    let baseURL: URL

    private func buildURL(path: String) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = path
        return components.url!
    }
}
