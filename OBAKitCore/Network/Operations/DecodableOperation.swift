//
//  DecodableOperation.swift
//  OBAKitCore
//
//  Created by Aaron Brethorst on 4/30/20.
//

import Foundation

protocol DataDecoder {
    func decode<T>(_ type: T.Type, from data: Data) throws -> T where T: Decodable
}

extension JSONDecoder: DataDecoder {}

public class DecodableOperation<T>: NetworkOperation where T: Decodable {
    private var modelData: T?
    private let type: T.Type
    private let decoder: DataDecoder

    convenience init(type: T.Type, decoder: DataDecoder, URL: URL, dataLoader: URLDataLoader) {
        self.init(type: type, decoder: decoder, request: NetworkOperation.buildRequest(for: URL), dataLoader: dataLoader)
    }

    init(type: T.Type, decoder: DataDecoder, request: URLRequest, dataLoader: URLDataLoader) {
        self.type = type
        self.decoder = decoder
        super.init(request: request, dataLoader: dataLoader)
    }

    // MARK: - State

    // MARK: - Completion Handler

    private var completionHandler: ((Result<T, Error>) -> Void)? {
        didSet {
            if isFinished {
                invokeCompletionHandler()
            }
        }
    }

    private func invokeCompletionHandler() {
        guard let handler = completionHandler else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if let error = self.error {
                handler(.failure(error))
            }
            else if let modelData = self.modelData {
                handler(.success(modelData))
            }
            else {
                handler(.failure(APIError.noResponseBody))
            }
        }

        completionHandler = nil
    }

    public func complete(completionHandler: @escaping ((Result<T, Error>) -> Void)) {
        self.completionHandler = completionHandler
    }

    // MARK: - Private

    override func set(data: Data?, response: HTTPURLResponse?, error: Error?) {
        super.set(data: data, response: response, error: error)

        defer {
            invokeCompletionHandler()
        }

        guard let response = response else {
            self.error = APIError.networkFailure(error)
            return
        }

        guard 200...299 ~= response.statusCode else {
            self.error = APIError.requestFailure(response)
            return
        }

        statusCodeIsEffectively404 = response.expectedContentLength == 0 && response.statusCode == 200

        guard response.hasJSONContentType else {
            if let error = error, errorLooksLikeCaptivePortal(error as NSError) {
                self.error = APIError.captivePortal
            }
            else {
                self.error = APIError.invalidContentType(originalError: error, expectedContentType: "JSON", actualContentType: response.contentType)
            }
            return
        }

        guard let data = data else {
            self.error = APIError.noResponseBody
            return
        }

        do {
            self.modelData = try decoder.decode(T.self, from: data)
        }
        catch let exception {
            let urlString = response.url?.absoluteString ?? "(Unknown URL)"
            print("Exception caught: \(urlString)")
            print(exception)
            self.error = exception
        }
    }

    private func errorLooksLikeCaptivePortal(_ error: NSError) -> Bool {
        if error.domain == NSCocoaErrorDomain && error.code == 3840 {
            return true
        }

        if error.domain == (kCFErrorDomainCFNetwork as String) && error.code == NSURLErrorAppTransportSecurityRequiresSecureConnection {
            return true
        }

        return false
    }

    /// Tries to tell you if you're effectively seeing a 404 'Not Found' error.
    ///
    /// The REST API doesn't do a good job of surfacing what should be 404 errors. If you request a
    /// valid endpoint, but provide it with a bogus piece of data (e.g. a non-existent Stop ID), it should
    /// return a 404 error to you. Instead, it gives a 200 and a blank body. This method tries to tell you
    /// if you're seeing an 'effective' 404.
    public private(set) var statusCodeIsEffectively404: Bool?
}
