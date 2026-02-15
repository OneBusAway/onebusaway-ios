//
//  ErrorClassifier.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreTelephony
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
    public static func classify(_ error: Error, regionName: String?) -> Error {
        // If it's already a well-classified APIError with good user messages, return as-is
        // — except for requestFailure, which we can upgrade to serverUnavailable.
        if let apiError = error as? APIError {
            return classifyAPIError(apiError, regionName: regionName)
        }

        // Classify NSURLError codes (timeout, no connection, etc.)
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return classifyURLError(nsError, regionName: regionName)
        }

        // Classify DecodingErrors: these surface as raw Swift messages
        // like "The data couldn't be read because it is missing."
        // When shown to users, this is confusing. Replace with a server-problem message.
        if error is DecodingError {
            return classifyDecodingError(error, regionName: regionName)
        }

        return error
    }

    // MARK: - Cellular Data Restriction Detection

    /// Returns `true` if iOS has restricted cellular data access for this app.
    public static var isCellularDataRestricted: Bool {
        let cellularData = CTCellularData()
        return cellularData.restrictedState == .restricted
    }

    // MARK: - Private Classification Methods

    private static func classifyAPIError(_ apiError: APIError, regionName: String?) -> Error {
        switch apiError {
        case .requestFailure(let response) where isServerError(statusCode: response.statusCode):
            // Upgrade generic requestFailure with 5xx status to a region-aware server-down message.
            guard let regionName else {
                logger.warning("Server error \(response.statusCode) but no region name available for user message.")
                return apiError
            }
            return APIError.serverUnavailable(
                regionName: regionName,
                statusCode: response.statusCode
            )

        case .networkFailure:
            // Check if the network failure is actually a cellular restriction.
            if isCellularDataRestricted {
                logger.info("Network failure reclassified as cellular data restriction.")
                return APIError.cellularDataRestricted
            }
            return apiError

        default:
            return apiError
        }
    }

    private static func classifyURLError(_ nsError: NSError, regionName: String?) -> Error {
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorDataNotAllowed:
            // Any of these can mean "cellular data restricted" when the toggle is off.
            if isCellularDataRestricted {
                logger.info("URL error \(nsError.code) reclassified as cellular data restriction.")
                return APIError.cellularDataRestricted
            }
            return APIError.networkFailure(nsError)

        case NSURLErrorTimedOut,
             NSURLErrorCannotConnectToHost,
             NSURLErrorCannotFindHost:
            // These suggest the server is unreachable rather than the user's network being down.
            guard let regionName else {
                return APIError.networkFailure(nsError)
            }
            return APIError.serverUnavailable(regionName: regionName, statusCode: nil)

        default:
            return APIError.networkFailure(nsError)
        }
    }

    private static func classifyDecodingError(_ error: Error, regionName: String?) -> Error {
        // A DecodingError typically means the server returned HTML, an error page,
        // or malformed JSON — all signs of a server-side problem.
        guard let regionName else {
            let fmt = OBALoc(
                "api_error.decoding_failure",
                value: "The server returned unexpected data. This usually means the server is experiencing problems. Please try again shortly.",
                comment: "An error shown when the server returns data the app can't understand, indicating a likely server-side issue."
            )
            return UnstructuredError(fmt)
        }

        return APIError.serverUnavailable(regionName: regionName, statusCode: nil)
    }

    // MARK: - Helpers

    private static func isServerError(statusCode: Int) -> Bool {
        return (500...599).contains(statusCode)
    }
}
