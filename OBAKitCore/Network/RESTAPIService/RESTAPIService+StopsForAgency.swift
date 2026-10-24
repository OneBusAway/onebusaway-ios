//
//  RESTAPIService+StopsForAgency.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// The answer to ``RESTAPIService/getStopsForAgency(id:ifNoneMatch:)``.
public enum StopsForAgencyResult: Sendable {
    /// The agency's stops, and the server's ETag if it sent one.
    case stops([Stop], etag: String?)

    /// The server answered 304: nothing changed since the ETag that was sent.
    case notModified
}

extension RESTAPIService {

    // MARK: - Region stop sync (#1555)

    /// What maglev, the Go OBA server, calls itself in `config.json`.
    static let maglevServerID = "oba-maglev"

    /// Retrieves every stop of one agency, with its routes, in one response.
    /// Neither the Java server nor maglev paginates this endpoint.
    ///
    /// Unlike the other calls, this builds its own request: a response can
    /// reach a few megabytes, so the timeout is longer than the usual 10 s; it
    /// never downloads in Low Data Mode; and it skips URLCache, so a
    /// conditional request gets the server's own 304 instead of a cached 200.
    /// The checks after the fetch repeat `getData(for:decodeAs:using:)`'s,
    /// which only takes a URL.
    ///
    /// - API Endpoint: `/api/where/stops-for-agency/{id}.json`. Java servers
    ///   added it in 2.6.0, and older ones answer with an HTML 404; see
    ///   ``APIError/meansStopsForAgencyUnsupported``.
    /// - Parameters:
    ///   - id: The agency ID.
    ///   - etag: Sent as `If-None-Match`. Only maglev's ETag identifies the data:
    ///     the Java server's changes on every response.
    /// - throws: ``APIError`` or a decoding error, unchanged, so the caller can
    ///   tell a server without the endpoint from a request that failed.
    public nonisolated func getStopsForAgency(id: String, ifNoneMatch etag: String? = nil) async throws -> StopsForAgencyResult {
        let url = urlBuilder.getStopsForAgency(id: id)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.allowsConstrainedNetworkAccess = false
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        // As in `getData(for:)`: some servers parse numbers by this locale.
        request.setValue("en-US", forHTTPHeaderField: "Accept-Language")
        if let etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await self.data(for: request)
        } catch APIError.requestFailure(let response) where response.statusCode == 304 {
            return .notModified
        }

        guard response.hasJSONContentType else {
            logger.error("Failed network request for \(url, privacy: .public): Invalid content type (actual: \(response.contentType ?? "<nil>", privacy: .public))")
            throw APIError.invalidContentType(originalError: nil, expectedContentType: "json", actualContentType: response.contentType)
        }

        // The Java server answers an unknown agency with a 200 whose body is `null`.
        if data.count < 10 && String(data: data, encoding: .utf8) == "null" {
            logger.error("Decoder failed for \(url, privacy: .public): endpoint returned the string 'null' instead of a real value.")
            throw APIError.invalidContentType(originalError: nil, expectedContentType: "json", actualContentType: "nothing")
        }

        do {
            let stops = try decoder.decode(RESTAPIResponse<[Stop]>.self, from: data).list
            return .stops(stops, etag: response.value(forHTTPHeaderField: "ETag"))
        } catch let error as DecodingError {
            logger.error("Decoder failed for \(url, privacy: .public): \(DecodingErrorReporter.message(from: error), privacy: .public)")
            DecodingErrorReporter.report(error: error, url: url, httpMethod: "GET")
            throw error
        }
    }

    /// Whether this region runs maglev, which identifies itself in `config.json`
    /// as `oba-maglev`; the Java server uses a bundle UUID or an empty string.
    /// Version numbers can't tell them apart: forks number their own versions,
    /// and maglev copies the Java server's `git.build.version` key.
    ///
    /// A maglev from before 2026-02-22 has no `config.json` route and answers
    /// with its web page. That reads as not maglev.
    public nonisolated func isMaglevServer() async throws -> Bool {
        do {
            let response = try await getData(for: urlBuilder.getConfig(), decodeRESTAPIResponseAs: ServerIdentity.self)
            return response.entry.id == Self.maglevServerID
        } catch let APIError.invalidContentType(_, _, actualContentType) {
            logger.info("config.json answered \(actualContentType ?? "<nil>", privacy: .public); treating the server as not maglev.")
            return false
        }
    }
}

/// The one field of `config.json` that tells servers apart.
nonisolated struct ServerIdentity: Decodable, Sendable {
    let id: String?
}

extension APIError {
    /// Whether a region's **first** `stops-for-agency` request failed because the
    /// server lacks the endpoint: an HTML page with a 404, as older Java servers
    /// send, or with a 200, as an old maglev's catch-all sends.
    ///
    /// Stricter than ``meansOnDemandUnsupported``, which also counts any 404 and
    /// the blank 200 that `APIService+GetData` maps to `.requestNotFound`. Here a
    /// blank 200 or a JSON 404 is a failed attempt to retry, not a missing
    /// endpoint (#1555).
    public var meansStopsForAgencyUnsupported: Bool {
        switch self {
        case .requestNotFound(let response):
            return response.statusCode == 404 && Self.isHTML(response.contentType)
        case .invalidContentType(_, _, let actualContentType):
            return Self.isHTML(actualContentType)
        default:
            return false
        }
    }

    private static func isHTML(_ contentType: String?) -> Bool {
        contentType?.lowercased().hasPrefix("text/html") ?? false
    }
}
