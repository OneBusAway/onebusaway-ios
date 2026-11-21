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
    ///   - timeoutPolicy: The timeout policy for the request (defaults to `.submission`, 15 seconds).
    /// - Returns: A decoded response of type `Response`.
    /// - Throws: `APIError` if the network request fails or decoding fails.
    nonisolated public func postData<Data: Encodable, Response: Decodable>(
        url: URL,
        data: Data,
        timeoutPolicy: RequestTimeoutPolicy = .submission
    ) async throws -> Response {
        try await sendData(url: url, method: .post, body: data, timeoutPolicy: timeoutPolicy)
    }

    /// Sends a PUT request to the given URL with the provided Encodable body.
    /// - Parameters:
    ///   - url: The endpoint URL.
    ///   - data: The Encodable body to update.
    ///   - timeoutPolicy: The timeout policy for the request (defaults to `.submission`, 15 seconds).
    /// - Returns: A decoded response of type `Response`.
    /// - Throws: `APIError` if the network request fails or decoding fails.
    nonisolated public func updateData<Data: Encodable, Response: Decodable>(
        url: URL,
        data: Data,
        timeoutPolicy: RequestTimeoutPolicy = .submission
    ) async throws -> Response {
        try await sendData(url: url, method: .put, body: data, timeoutPolicy: timeoutPolicy)
    }

    /// Sends an encoded request body using the specified HTTP method and decodes the response.
    /// - Parameters:
    ///   - url: The endpoint URL.
    ///   - method: The HTTP method to use (e.g., POST, PUT).
    ///   - body: The `Encodable` payload to send.
    ///   - timeoutPolicy: The timeout policy for the request.
    /// - Returns: The decoded response of type `Response`.
    /// - Throws: `APIError` for network or decoding failures.
    nonisolated private func sendData<Data: Encodable, Response: Decodable>(
        url: URL,
        method: HTTPMethod,
        body: Data,
        timeoutPolicy: RequestTimeoutPolicy = .submission
    ) async throws -> Response {
        try Task.checkCancellation()

        let encoder = JSONEncoder()
        let requestData = try encoder.encode(body)

        var request = URLRequest(url: url, timeoutInterval: timeoutPolicy.interval)
        request.httpMethod = method.value
        request.httpBody = requestData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("en-US", forHTTPHeaderField: "Accept-Language")

        let (data, response): (Foundation.Data, URLResponse)

        do {
            (data, response) = try await dataLoader.data(for: request)
        } catch let error as NSError {
            logger.error("Failed network request for \(request.loggableURL, privacy: .public): \(ErrorReport.sanitizedForReporting(error) as NSError, privacy: .public)")

            if Self.errorLooksLikeCaptivePortal(error) {
                throw APIError.captivePortal
            } else {
                throw error
            }
        }

        try handleSendDataHttpResponse(response, url, method)

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch let error as DecodingError {
            let message = DecodingErrorReporter.message(from: error)
            logger.error("Decoder failed for \(ErrorReport.stripQuery(url), privacy: .public): \(message, privacy: .public)")
            DecodingErrorReporter.report(error: error, url: url, httpMethod: method.value)
            throw error.withRequestURL(url)
        } catch {
            logger.error("Decoder failed for \(ErrorReport.stripQuery(url), privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func handleSendDataHttpResponse(_ response: URLResponse, _ url: URL, _ method: HTTPMethod) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("Network error: missing response for \(method.value) \(ErrorReport.stripQuery(response.url ?? url), privacy: .public)")
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
