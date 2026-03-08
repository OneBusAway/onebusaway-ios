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

    private static let logger = os.Logger(
        subsystem: "org.onebusaway.iphone",
        category: "ErrorClassifier"
    )

    // MARK: - Public API

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
            case .serverError, .serverUnavailable, .cellularDataRestricted:
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
        // Replace with a server-problem message.
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

        case .requestFailure(let response) where isServerUnavailable(statusCode: response.statusCode):
            guard let regionName else {
                logger.warning("Server error \(response.statusCode) but no region name available for user message.")
                return apiError
            }
            return APIError.serverUnavailable(regionName: regionName, statusCode: response.statusCode)

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
            return APIError.serverUnavailable(regionName: regionName, statusCode: nil)

        default:
            return APIError.networkFailure(nsError)
        }
    }

    private static func classifyDecodingError(_ error: Error, regionName: String?) -> Error {
        guard let regionName else {
            let message = OBALoc(
                "api_error.decoding_failure",
                value: "The server returned unexpected data. This usually means the server is experiencing problems. Please try again shortly.",
                comment: "An error shown when the server returns data the app can't understand, indicating a likely server-side issue."
            )
            return UnstructuredError(message)
        }

        return APIError.serverUnavailable(regionName: regionName, statusCode: nil)
    }

    // MARK: - Helpers

    private static func isServerUnavailable(statusCode: Int) -> Bool {
        return [502, 503, 504].contains(statusCode)
    }
}
