//
//  AgencyFeedStatus.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Tracks the status of a vehicle feed for a single agency
struct AgencyFeedStatus: Identifiable {
    let id: String  // agencyID
    let agencyName: String
    var lastFetchedAt: Date?
    var vehicleCount: Int = 0
    var error: FeedError?
    var httpStatusCode: Int?
    var dataSize: Int?
    var isSkipped: Bool = false  // True if agency was disabled and not fetched

    /// Errors that can occur when fetching a vehicle feed
    enum FeedError {
        case invalidURL
        case networkError(Error)
        case httpError(Int)
        case decodingError(Error)

        /// A user-friendly description of the error
        var userFriendlyDescription: String {
            switch self {
            case .invalidURL:
                return "The feed address is invalid."
            case .networkError(let error):
                let nsError = error as NSError
                if nsError.code == NSURLErrorNotConnectedToInternet {
                    return "No internet connection. Check your network settings."
                } else if nsError.code == NSURLErrorTimedOut {
                    return "The request timed out. The server may be busy."
                }
                return "Unable to connect to the server. Please try again later."
            case .httpError(let code):
                switch code {
                case 404:
                    return "This agency doesn't provide a vehicle feed."
                case 500...599:
                    return "The server is having problems. Please try again later."
                default:
                    return "Server returned an error (code \(code))."
                }
            case .decodingError:
                return "The feed data couldn't be read. It may be in an unexpected format."
            }
        }
    }

    /// A short description of the current status
    var statusDescription: String {
        if let error = error {
            return error.userFriendlyDescription
        }
        return "\(vehicleCount) vehicles"
    }

    /// Whether the feed was successfully fetched with vehicles
    var isSuccess: Bool {
        error == nil && vehicleCount > 0
    }
}
