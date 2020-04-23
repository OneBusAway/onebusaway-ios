//
//  NetworkOperation.swift
//  OBAKitCore
//
//  Created by Aaron Brethorst on 4/30/20.
//

import Foundation

public protocol Requestable {
    var request: URLRequest { get }
}

public enum APIError: Error {
    case networkFailure(Error)
    case invalidData(Error)
    case noResponseBody
}

/// This class makes API calls to the OBA REST service and converts the server's responses into model objects.
///
/// - NOTE: The code in this class is largely identical to `ObacoOperation`. If a change is made here,
/// please be sure to make a change in that file too. Search for the text `AB-20200427` to find that reference.
public class NetworkOperation: AsyncOperation, Requestable {
    public let request: URLRequest
    public private(set) var response: HTTPURLResponse?
    public private(set) var data: Data?
    private var dataTask: URLSessionDataTask?

    public convenience init(url: URL) {
        self.init(request: NetworkOperation.buildRequest(for: url))
    }

    public init(request: URLRequest) {
        self.request = request
        super.init()
        self.name = request.url?.absoluteString ?? "(Unknown)"
    }

    public override func start() {
        super.start()

        let task = URLSession.shared.dataTask(with: request) { [weak self] (data, response, error) in
            guard
                let self = self,
                !self.isCancelled,
                let response = response as? HTTPURLResponse
            else {
                return
            }

            self.set(data: data, response: response, error: error)

            self.finish()
        }

        task.resume()
        self.dataTask = task
    }

    override func finish() {
        super.finish()

        // nop?
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
