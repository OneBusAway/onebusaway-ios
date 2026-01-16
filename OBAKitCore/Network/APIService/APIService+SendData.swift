//
//  APIService+SendData.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

extension APIService {

    /// Sends a POST request to the given URL with the provided Encodable body.
    /// - Parameters:
    ///   - url: The endpoint URL.
    ///   - data: The Encodable body to send.
    /// - Returns: A decoded response of type `Response`.
    /// - Throws: `APIError` if the network request fails or decoding fails.
    nonisolated public func postData<Data: Encodable, Response: Decodable>(url: URL, data: Data) async throws -> Response {
        try await sendData(url: url, method: .post, body: data)
    }

    /// Sends a PUT request to the given URL with the provided Encodable body.
    /// - Parameters:
    ///   - url: The endpoint URL.
    ///   - data: The Encodable body to update.
    /// - Returns: A decoded response of type `Response`.
    /// - Throws: `APIError` if the network request fails or decoding fails.
    nonisolated public func updateData<Data: Encodable, Response: Decodable>(url: URL, data: Data) async throws -> Response {
        try await sendData(url: url, method: .put, body: data)
    }

    /// Sends an encoded request body using the specified HTTP method and decodes the response.
    /// - Parameters:
    ///   - url: The endpoint URL.
    ///   - method: The HTTP method to use (e.g., POST, PUT).
    ///   - body: The `Encodable` payload to send.
    /// - Returns: The decoded response of type `Response`.
    /// - Throws: `APIError` for network or decoding failures.
    nonisolated private func sendData<Data: Encodable, Response: Decodable>(url: URL, method: HTTPMethod, body: Data) async throws -> Response {

        let encoder = JSONEncoder()
        let requestData = try encoder.encode(body)

        var request = URLRequest(url: url)
        request.httpMethod = method.value
        request.httpBody = requestData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response): (Foundation.Data, URLResponse)

        do {
            (data, response) = try await dataLoader.data(for: request)
        } catch let error as NSError {
            logger.error("Failed network request for \(request.description, privacy: .public): \(error, privacy: .public)")

            if errorLooksLikeCaptivePortal(error) {
                throw APIError.captivePortal
            } else {
                throw error
            }
        }

        try handleSendDateHttpResponse(response, url, method)

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch let error as DecodingError {
            let message = DecodingErrorReporter.message(from: error)
            logger.error("DECODING ERROR: \(message, privacy: .public)")
            throw NSError(
                domain: "DecodingError",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        } catch {
            logger.error("UNEXPECTED DECODING ERROR: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func handleSendDateHttpResponse(_ response: URLResponse, _ url: URL, _ method: HTTPMethod) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("Network error: missing response for \(method.value) \(response.url ?? URL(string: "")!, privacy: .public)")
            throw APIError.networkFailure(nil)
        }

        guard 200...299 ~= httpResponse.statusCode else {
            if httpResponse.statusCode == 404 {
                throw APIError.requestNotFound(httpResponse)
            }
            throw APIError.requestFailure(httpResponse)
        }

    }
}
