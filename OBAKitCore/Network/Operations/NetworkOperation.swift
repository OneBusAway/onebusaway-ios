//
//  NetworkOperation.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

public enum APIError: Error, LocalizedError {
    case captivePortal
    case invalidContentType(originalError: Error?, expectedContentType: String, actualContentType: String?)
    case networkFailure(Error?)
    case noResponseBody
    case requestFailure(HTTPURLResponse)

    /// A `404` error.
    case requestNotFound(HTTPURLResponse)

    /// The user has disabled cellular data for this app in iOS Settings.
    case cellularDataRestricted

    /// The regional server returned a 500 Internal Server Error but is still running.
    case serverError(regionName: String)

    /// The regional server is down or unreachable (502, 503, 504, or timeout).
    case serverUnavailable(regionName: String, statusCode: Int?)

    /// The regional server returned a body this app cannot decode. Distinct from
    /// `.serverUnavailable`: the host responded, the payload is unusable (#1276).
    case invalidResponseData(regionName: String)

    /// Survey service is not configured or survey base URL is missing.
    case surveyServiceNotConfigured

    /// No region has been selected.
    case noRegionSelected

    public var errorDescription: String? {
        switch self {
        case .captivePortal:
            return OBALoc(
                "api_error.captive_portal",
                value: "It looks like you are connected to a WiFi network that won't let you access the Internet. Try disconnecting from WiFi or authenticating with the network to proceed.",
                comment: "An error message that tells the user that they are connected to a captive portal WiFi network."
            )
        case .invalidContentType(_, let expectedContentType, let actualContentType):
            let fmt = OBALoc(
                "api_error.invalid_content_type_fmt",
                value: "Expected to receive %@ data from the server, but we received %@ instead.",
                comment: "An error message that informs the user that the wrong kind of content was received from the server."
            )
            return String(format: fmt, expectedContentType, actualContentType ?? "(nil)")
        case .networkFailure(let error):
            guard let error = error else {
                return OBALoc(
                    "api_error.network_failure",
                    value: "Unable to connect to the Internet or the server. Please check your network connection and try again.",
                    comment: "An error that tells the user that the network connection isn't working."
                )
            }

            let nsError = error as NSError
            let message = nsError.localizedDescription
            guard
                let failingURL = nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL,
                let components = URLComponents(url: failingURL, resolvingAgainstBaseURL: false),
                let host = components.host
            else {
                return message
            }

            return String(format: "%@ %@", message, host)

        case .noResponseBody:
            return OBALoc(
                "api_error.no_response_body",
                value: "The server unexpectedly didn't return any data in response to your request.",
                comment: "An error that tells the user that the server unexpectedly failed to return data."
            )
        case .requestFailure(let response):
            let fmt = OBALoc(
                "api_error.request_failure_fmt",
                value: "The server encountered an error while trying to respond to your request, producing the status code %d. (URL: %@)",
                comment: "An error that is produced in response to HTTP status codes outside of 200-299."
            )
            return String(format: fmt, response.statusCode, String(response.url?.absoluteString.split(separator: "?").first ?? "(nil)"))
        case .requestNotFound(let response):
            let fmt = OBALoc(
                "api_error.request_not_found",
                value: "404 Not found (%@)",
                comment: "An error that is produced in response to HTTP status code 404"
            )
            return String(format: fmt, response.url?.absoluteString ?? "(nil)")
        case .cellularDataRestricted:
            let fmt = OBALoc(
                "api_error.cellular_data_restricted_fmt",
                value: "%@ is not currently allowed to access cellular data. To fix this, go to Settings > Cellular and enable cellular data for %@, or connect to a WiFi network.",
                comment: "An error that tells the user that cellular data access is disabled for this app in iOS Settings. Both substituted values are the app name."
            )
            return String(format: fmt, Bundle.main.appName, Bundle.main.appName)
        case .serverError(let regionName):
            let fmt = OBALoc(
                "api_error.server_error_fmt",
                value: "The server for %@ encountered an error while handling your request. Please try again.",
                comment: "An error shown when the server returns a 500 Internal Server Error. The substituted value is the region name, e.g. 'Puget Sound'."
            )
            return String(format: fmt, regionName)
        case .serverUnavailable(let regionName, _):
            let fmt = OBALoc(
                "api_error.server_unavailable_fmt",
                value: "Unable to reach the server for %@. %@ can't show transit information for this region right now. The server may be down, or a VPN or firewall may be blocking it.",
                comment: "An error shown when the regional transit server cannot be reached. Mentions VPN because riders often hit this with a working phone on a filtered network. The first substituted value is the region name, the second is the app name."
            )
            return String(format: fmt, regionName, Bundle.main.appName)
        case .invalidResponseData(let regionName):
            let fmt = OBALoc(
                "api_error.invalid_response_data_fmt",
                value: "The server for %@ returned data this app can't read. That's usually a problem with the stop or agency feed, not with %@. Try again shortly.",
                comment: "An error shown when the regional server returned a body the app cannot decode. Distinct from a down server. The first substituted value is the region name, the second is the app name."
            )
            return String(format: fmt, regionName, Bundle.main.appName)
        case .surveyServiceNotConfigured:
            return OBALoc("api_error.survey_service_not_configured", value: "Survey service is not available in this region.", comment: "An error message that tells the user that surveys are not available.")
        case .noRegionSelected:
            return OBALoc("api_error.no_region_selected", value: "No region has been selected. Please select a region to continue.", comment: "An error message that tells the user that no region has been selected.")
        }
    }

    /// Missing-stop shapes shared by the Bookmarks tab and the stop page.
    ///
    /// - Literal HTTP 404: the stop no longer resolves.
    /// - HTTP 200 with body `null`: what many OBA servers send instead of a
    ///   404. `APIService+GetData` throws that as `invalidContentType(...,
    ///   "json", "nothing")`.
    ///
    /// Empty HTTP 200 is *not* included; a live stop can return a full 200, so
    /// an empty body stays a transient error.
    nonisolated public var isGoneStopResponse: Bool {
        switch self {
        case .requestNotFound(let response) where response.statusCode == 404:
            return true
        case .invalidContentType(_, let expected, let actual)
            where expected == "json" && actual == "nothing":
            return true
        default:
            return false
        }
    }
}
