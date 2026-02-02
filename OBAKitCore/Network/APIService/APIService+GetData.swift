//
//  APIService+GetData.swift
//  OBAKitCore
//
//  Created by Alan Chu on 12/28/22.
//

import Foundation
#if canImport(CFNetwork)
import CFNetwork
#endif

extension APIService {
    nonisolated func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response): (Data, URLResponse)
        do {
            logger.info("Begin network request for \(request.description, privacy: .public)")
            (data, response) = try await dataLoader.data(for: request)
            logger.info("Finish network request for \(request.description, privacy: .public)")
        } catch let error as NSError {
            logger.error("Failed network request for \(request.description, privacy: .public): \(error, privacy: .public)")
            if errorLooksLikeCaptivePortal(error) {
                throw APIError.captivePortal
            } else {
                throw error
            }
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("Failed network request for \(request.description, privacy: .public): missing response.")
            throw APIError.networkFailure(nil)
        }

        guard 200...299 ~= httpResponse.statusCode else {
            if httpResponse.statusCode == 404 {
                logger.error("Failed network request for \(request.description, privacy: .public): 404 not found.")
                throw APIError.requestNotFound(httpResponse)
            } else {
                logger.error("Failed network request for \(request.description, privacy: .public): \(httpResponse).")
                throw APIError.requestFailure(httpResponse)
            }
        }

        // The REST API doesn't do a good job of surfacing what should be 404 errors.
        // If you request a valid endpoint, but provide it with a bogus piece of
        // data (e.g. a non-existent Stop ID), it should return a 404 error to you.
        // Instead, it gives a 200 and a blank body.
        if httpResponse.expectedContentLength == 0 && httpResponse.statusCode == 200 {
            logger.error("Failed network request for \(request.description, privacy: .public): 404 not found.")
            throw APIError.requestNotFound(httpResponse)
        }

        if request.httpMethod == "GET" && data.isEmpty {
            logger.error("Failed network request for \(request.description, privacy: .public): missing response body.")
            throw APIError.noResponseBody
        }

        return (data, httpResponse)
    }

    nonisolated func getData(for url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 10.0)
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("en-US", forHTTPHeaderField: "Accept-Language")

        return try await data(for: request)
    }

    nonisolated func getData<T: Decodable>(for url: URL, decodeAs: T.Type, using decoder: DataDecoder) async throws -> T {
        let (data, response) = try await self.getData(for: url)

        guard response.hasJSONContentType else {
            logger.error("Failed network request for \(url, privacy: .public): Invalid content type (actual: \(response.contentType ?? "<nil>", privacy: .public))")
            throw APIError.invalidContentType(originalError: nil, expectedContentType: "json", actualContentType: response.contentType)
        }

        if data.count < 10 && String(data: data, encoding: .utf8) == "null" {
            // 10 ^^^ is arbitrary. This could really be 8 or maybe even 4, but this is a
            // belt and suspenders check.
            logger.error("Decoder failed for \(url, privacy: .public): endpoint returned the string 'null' instead of a real value.")
            throw APIError.invalidContentType(originalError: nil, expectedContentType: "json", actualContentType: "nothing")
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            logger.error("Decoder failed for \(url, privacy: .public): \(error, privacy: .public)")
            throw error
        }
    }

    /// Convenience.
    nonisolated func getData<T: Decodable>(for url: URL, decodeRESTAPIResponseAs decodeType: T.Type, using decoder: DataDecoder) async throws -> RESTAPIResponse<T> {
        return try await getData(for: url, decodeAs: RESTAPIResponse<T>.self, using: decoder)
    }

    nonisolated func errorLooksLikeCaptivePortal(_ error: NSError) -> Bool {
        if error.domain == NSCocoaErrorDomain && error.code == 3840 {
            return true
        }

        #if os(watchOS)
        let cfNetworkDomain = "kCFErrorDomainCFNetwork"
        #else
        let cfNetworkDomain = kCFErrorDomainCFNetwork as String
        #endif

        if error.domain == cfNetworkDomain && error.code == NSURLErrorAppTransportSecurityRequiresSecureConnection {
            return true
        }

        return false
    }
}
