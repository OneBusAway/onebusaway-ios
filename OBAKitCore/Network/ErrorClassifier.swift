//
//  ErrorClassifier.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import os.log

/// Classifies raw network errors into user-friendly `APIError` cases.
public enum ErrorClassifier {

    /// Stable buckets for telemetry, retry policy, and support tooling.
    public enum Category: String, Sendable, Equatable {
        case timeout
        case offline
        case server
        case decoding
        case authentication
        case unknown
    }

    private static let logger = os.Logger(
        subsystem: "org.onebusaway.iphone",
        category: "ErrorClassifier"
    )

    // MARK: - Public API

    /// Returns the stable category for a raw or already-classified error.
    public static func category(for error: Error) -> Category {
        if let apiError = error as? APIError {
            switch apiError {
            case .requestFailure(let response):
                switch response.statusCode {
                case 401, 403: return .authentication
                case 429, 500...599: return .server
                case 408: return .timeout
                default: return .unknown
                }
            case .serverUnavailable(_, _, let inner):
                return inner.map { category(for: $0) } ?? .server
            case .serverError, .rateLimited:
                return .server
            case .invalidResponseData, .invalidContentType, .noResponseBody:
                return .decoding
            case .requestNotFound(let response):
                // A blank 200 arrives as `requestNotFound` too, and classifies
                // to `invalidResponseData`.
                return response.statusCode == 404 ? .unknown : .decoding
            case .networkFailure(let inner):
                return inner.map { category(for: $0) } ?? .offline
            case .captivePortal, .cellularDataRestricted:
                return .offline
            default:
                return .unknown
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut:
                return .timeout
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorDataNotAllowed:
                return .offline
            case NSURLErrorCannotConnectToHost,
                 NSURLErrorCannotFindHost:
                return .server
            default:
                return .unknown
            }
        }

        return error is DecodingError || error is UnreadableResponseError ? .decoding : .unknown
    }

    /// Classifies a raw `Error` into a more specific, user-friendly `APIError`.
    ///
    /// - Parameters:
    ///   - error: The original error thrown during a network or decoding operation.
    ///   - regionName: The display name of the current region, used in server-down messages.
    ///   - isCellularDataRestricted: Whether the user has disabled cellular data for this app in iOS Settings.
    public static func classify(_ error: Error, regionName: String?, isCellularDataRestricted: Bool = false) -> Error {
        // Already-classified errors pass through unchanged.
        if let apiError = error as? APIError {
            switch apiError {
            case .serverError, .serverUnavailable, .invalidResponseData, .cellularDataRestricted, .rateLimited:
                return apiError
            default:
                return classifyAPIError(apiError, regionName: regionName, isCellularDataRestricted: isCellularDataRestricted)
            }
        }

        // Classify NSURLError codes (timeout, no connection, etc.)
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return classifyURLError(nsError, regionName: regionName, isCellularDataRestricted: isCellularDataRestricted)
        }

        // DecodingErrors surface raw Swift messages like
        // "The data couldn't be read because it is missing."
        // That is bad payload, not an unreachable host (#1276).
        if error is DecodingError {
            return classifyDecodingError(error, regionName: regionName)
        }

        return error
    }

    // MARK: - Private Classification Methods

    private static func classifyAPIError(_ apiError: APIError, regionName: String?, isCellularDataRestricted: Bool) -> Error {
        switch apiError {
        case .requestFailure(let response) where response.statusCode == 500:
            guard let regionName else {
                logger.warning("Server error 500 but no region name available for user message.")
                return apiError
            }
            return APIError.serverError(regionName: regionName)

        case .requestFailure(let response) where response.statusCode == 429:
            // Before this case existed, 429 fell through to `requestFailure`'s
            // "the server encountered an error" copy (#1582).
            return APIError.rateLimited

        case .requestFailure(let response) where isServerUnavailable(statusCode: response.statusCode):
            guard let regionName else {
                logger.warning("Server error \(response.statusCode) but no region name available for user message.")
                return apiError
            }
            return APIError.serverUnavailable(regionName: regionName, statusCode: response.statusCode)

        case .requestNotFound(let response) where response.statusCode != 404:
            // `APIService+GetData` throws `requestNotFound` for a blank HTTP 200 as
            // well as for a literal 404, but `errorDescription` says "404 Not found
            // (url)" either way — a raw URL and a status code the server never sent.
            // The host answered; the body was unusable. Say that instead (#1336).
            guard let regionName else {
                // Returning `apiError` here would hand back the very "404 Not found"
                // copy this case exists to prevent, so fall back to the region-less
                // wording instead — same treatment `classifyDecodingError` gives it.
                logger.warning("Empty-body \(response.statusCode) but no region name available for user message.")
                return regionlessInvalidResponseError()
            }
            return APIError.invalidResponseData(regionName: regionName)

        case .networkFailure:
            if isCellularDataRestricted {
                logger.info("Network failure reclassified as cellular data restriction.")
                return APIError.cellularDataRestricted
            }
            return apiError

        default:
            return apiError
        }
    }

    private static func classifyURLError(_ nsError: NSError, regionName: String?, isCellularDataRestricted: Bool) -> Error {
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorDataNotAllowed:
            if isCellularDataRestricted {
                logger.info("URL error \(nsError.code) reclassified as cellular data restriction.")
                return APIError.cellularDataRestricted
            }
            return APIError.networkFailure(nsError)

        case NSURLErrorTimedOut,
             NSURLErrorCannotConnectToHost,
             NSURLErrorCannotFindHost:
            guard let regionName else {
                logger.warning("Server unreachable (URL error \(nsError.code)) but no region name available for user message.")
                return APIError.networkFailure(nsError)
            }
            return APIError.serverUnavailable(regionName: regionName, statusCode: nil, underlyingError: nsError)

        default:
            return APIError.networkFailure(nsError)
        }
    }

    private static func classifyDecodingError(_ error: Error, regionName: String?) -> Error {
        guard let regionName else {
            return regionlessInvalidResponseError()
        }

        return APIError.invalidResponseData(regionName: regionName)
    }

    /// The unusable-payload message for the two paths that reach it without a
    /// region name to specialize the copy with.
    private static func regionlessInvalidResponseError() -> Error {
        let message = OBALoc(
            "api_error.decoding_failure",
            value: "The server returned data this app can't read. That's usually a problem with the stop or agency feed. Please try again shortly.",
            comment: "An error shown when the server returns a body the app cannot decode and no region name is available to specialize the copy."
        )
        return UnreadableResponseError(errorDescription: message)
    }

    /// The region-less unusable-payload error. Its own type rather than an
    /// `UnstructuredError`, so `category(for:)` still sees a decoding failure
    /// after classification (#1733).
    struct UnreadableResponseError: LocalizedError {
        let errorDescription: String?
    }

    // MARK: - Helpers

    private static func isServerUnavailable(statusCode: Int) -> Bool {
        return [502, 503, 504].contains(statusCode)
    }
}
