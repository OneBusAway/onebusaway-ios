//
//  RESTAPIService+Processing.swift
//  OBAKitCore
//
//  Created by Alan Chu on 12/28/22.
//

import Foundation

extension RESTAPIService {
    nonisolated func getData(for url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 10.0)
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await dataLoader.data(for: request)
        } catch (let error as NSError) {
            if errorLooksLikeCaptivePortal(error) {
                throw APIError.captivePortal
            } else {
                throw error
            }
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkFailure(nil)
        }

        guard 200...299 ~= httpResponse.statusCode else {
            if httpResponse.statusCode == 404 {
                throw APIError.requestNotFound(httpResponse)
            } else {
                throw APIError.requestFailure(httpResponse)
            }
        }

        // The REST API doesn't do a good job of surfacing what should be 404 errors.
        // If you request a valid endpoint, but provide it with a bogus piece of
        // data (e.g. a non-existent Stop ID), it should return a 404 error to you.
        // Instead, it gives a 200 and a blank body.
        if httpResponse.expectedContentLength == 0 && httpResponse.statusCode == 200 {
            throw APIError.requestNotFound(httpResponse)
        }

        guard httpResponse.hasJSONContentType else {
            throw APIError.invalidContentType(originalError: nil, expectedContentType: "json", actualContentType: httpResponse.contentType)
        }

        guard data.isEmpty == false else {
            throw APIError.noResponseBody
        }

        return (data, httpResponse)
    }

    nonisolated func getData<T: Decodable>(for url: URL, decodeAs: T.Type) async throws -> T {
        let (data, response) = try await self.getData(for: url)

        do {
            return try self.decoder.decode(T.self, from: data)
        } catch {
            await logError(response, "decoder failed: \(error)")
            throw error
        }
    }

    /// Convenience.
    nonisolated func getData<T: Decodable>(for url: URL, decodeRESTAPIResponseAs decodeType: T.Type) async throws -> RESTAPIResponse<T> {
        return try await getData(for: url, decodeAs: RESTAPIResponse<T>.self)
    }

    private nonisolated func errorLooksLikeCaptivePortal(_ error: NSError) -> Bool {
        if error.domain == NSCocoaErrorDomain && error.code == 3840 {
            return true
        }

        if error.domain == (kCFErrorDomainCFNetwork as String) && error.code == NSURLErrorAppTransportSecurityRequiresSecureConnection {
            return true
        }

        return false
    }
}
