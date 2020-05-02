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

    override func finish() {
        super.finish()

        invokeCompletionHandler()
    }

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

        do {
            if response?.statusCode == 200 {
                if let data = data {
                    self.modelData = try decoder.decode(T.self, from: data)
                }
            }
            else {
                self.error = APIError.noResponseBody
            }
        }
        catch let exception {
            let urlString = response?.url?.absoluteString ?? "(Unknown URL)"
            print("Exception caught: \(urlString)")
            print(exception)
            self.error = exception
        }
    }
}
