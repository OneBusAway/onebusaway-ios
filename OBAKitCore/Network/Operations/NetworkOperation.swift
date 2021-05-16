//
//  NetworkOperation.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

public protocol Requestable {
    var request: URLRequest { get }
}

public enum APIError: Error, LocalizedError {
    case captivePortal
    case invalidContentType(originalError: Error?, expectedContentType: String, actualContentType: String?)
    case networkFailure(Error?)
    case noResponseBody
    case requestFailure(HTTPURLResponse)

    public var errorDescription: String? {
        switch self {
        case .captivePortal:
            return OBALoc("api_error.captive_portal", value: "It looks like you are connected to a WiFi network that won't let you access the Internet. Try disconnecting from WiFi or authenticating with the network to proceed.", comment: "An error message that tells the user that they are connected to a captive portal WiFi network.")
        case .invalidContentType(_, let expectedContentType, let actualContentType):
            let fmt = OBALoc("api_error.invalid_content_type_fmt", value: "Expected to receive %@ data from the server, but we received %@ instead.", comment: "An error message that informs the user that the wrong kind of content was received from the server.")
            return String(format: fmt, expectedContentType, actualContentType ?? "(nil)")
        case .networkFailure(let error):
            guard let error = error else {
                return OBALoc("api_error.network_failure_fmt", value: "Unable to connect to the Internet or the server. Please check your network connection and try again.", comment: "An error that tells the user that the network connection isn't working.")
            }

            let nsError = error as NSError
            let message = nsError.localizedDescription
            guard
                let failingURL = nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL,
                let components = URLComponents(url: failingURL, resolvingAgainstBaseURL: false),
                let host = components.host
            else {
                return message
            }

            return String(format: "%@ %@", message, host)

        case .noResponseBody:
            return OBALoc("api_error.no_response_body", value: "The server unexpectedly didn't return any data in response to your request.", comment: "An error that tells the user that the server unexpectedly failed to return data.")
        case .requestFailure(let response):
            let fmt = OBALoc("api_error.request_failure_fmt", value: "The server encountered an error while trying to respond to your request, producing the status code %d. (URL: %@)", comment: "An error that is produced in response to HTTP status codes outside of 200-299.")
            return String(format: fmt, response.statusCode, String(response.url?.absoluteString.split(separator: "?").first ?? "(nil)"))
        }
    }
}

/// This class makes API calls to the OBA REST service and converts the server's responses into model objects.
///
/// - NOTE: The code in this class is largely identical to `ObacoOperation`. If a change is made here,
/// please be sure to make a change in that file too. Search for the text `AB-20200427` to find that reference.
public class NetworkOperation: AsyncOperation, Requestable {
    public let request: URLRequest
    public private(set) var response: HTTPURLResponse?
    public private(set) var data: Data?

    public let progress: Progress = Progress(totalUnitCount: 1)

    private var dataTask: URLSessionDataTask?
    private let dataLoader: URLDataLoader

    public convenience init(url: URL, dataLoader: URLDataLoader) {
        self.init(request: NetworkOperation.buildRequest(for: url), dataLoader: dataLoader)
    }

    public init(request: URLRequest, dataLoader: URLDataLoader) {
        self.request = request
        self.dataLoader = dataLoader
        super.init()
        self.name = request.url?.absoluteString ?? "(Unknown)"
    }

    public override func start() {
        super.start()

        let task = dataLoader.dataTask(with: request) { [weak self] (data, response, error) in
            guard let self = self, !self.isCancelled else { return }

            self.set(data: data, response: response as? HTTPURLResponse, error: error)
            self.finish()
        }
        progress.addChild(task.progress, withPendingUnitCount: 1)
        task.resume()
        self.dataTask = task
    }

    func set(data: Data?, response: HTTPURLResponse?, error: Error?) {
        self.data = data
        self.response = response
        self.error = error
    }

    public override func cancel() {
        super.cancel()
        dataTask?.cancel()
        finish()
    }

    class func buildRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 10.0)
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")

        return request
    }
}
