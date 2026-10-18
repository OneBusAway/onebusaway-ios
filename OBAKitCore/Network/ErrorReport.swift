//
//  ErrorReport.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Everything the app says about one failed request: rider-facing copy for the
/// toast and the Problem Details page, plus the support details a screenshot of
/// that page carries (#1582).
///
/// The copy is put together from two parts. The ``Subject`` comes from the
/// request's endpoint and says *what* failed ("Couldn't load arrival times").
/// The ``Cause`` comes from the classified error and says *why*. Every pair has
/// sensible copy, and anything unrecognized uses the ``Cause/fallback`` wording.
public struct ErrorReport: Sendable {

    // MARK: - Subject

    /// What failed, worked out from the endpoint of the request that failed.
    public enum Subject: Sendable, Equatable {
        case arrivalTimes
        case livePosition
        case schedule
        case nearbyStops
        case routeMap
        case searchResults
        case serviceAlerts
        case bikeShare
        case unknown

        /// Matches path components rather than whole paths so the same table
        /// covers OBA REST (`/api/where/trip-details/1_123.json`), the sidecar,
        /// and GBFS feeds.
        public init(url: URL?) {
            let components = (url?.pathComponents ?? []).map { $0.lowercased() }
            func has(_ prefixes: String...) -> Bool {
                components.contains { component in prefixes.contains { component.hasPrefix($0) } }
            }

            if has("arrivals-and-departures-for-stop", "arrival-and-departure-for-stop") {
                self = .arrivalTimes
            } else if has("trip-details", "trip-for-vehicle", "trips-for-route") {
                self = .livePosition
            } else if has("schedule-for-stop", "schedule-for-route") {
                self = .schedule
            } else if has("stops-for-location", "routes-for-location") {
                self = .nearbyStops
            } else if has("stops-for-route", "shape") {
                self = .routeMap
            } else if has("search") {
                self = .searchResults
            } else if has("alerts", "situation") {
                self = .serviceAlerts
            } else if has("gbfs", "free_bike_status", "station_status", "vehicle_status") {
                self = .bikeShare
            } else if components.contains("stop") {
                // `stop/1_75403.json` — the stop page's own fetch. An exact match:
                // a prefix would also catch `stops-for-agency`.
                self = .arrivalTimes
            } else {
                self = .unknown
            }
        }

        /// "Couldn't load …", written out in full per subject rather than
        /// assembled from a noun, so translators get a whole sentence.
        public var title: String {
            switch self {
            case .arrivalTimes:
                return OBALoc("error_report.title.arrival_times", value: "Couldn't load arrival times", comment: "Title of an error about a failed request for a stop's arrival times.")
            case .livePosition:
                return OBALoc("error_report.title.live_position", value: "Couldn't load live position", comment: "Title of an error about a failed request for a vehicle's live position.")
            case .schedule:
                return OBALoc("error_report.title.schedule", value: "Couldn't load the schedule", comment: "Title of an error about a failed request for a schedule.")
            case .nearbyStops:
                return OBALoc("error_report.title.nearby_stops", value: "Couldn't load nearby stops", comment: "Title of an error about a failed request for the stops near the rider.")
            case .routeMap:
                return OBALoc("error_report.title.route_map", value: "Couldn't load the route map", comment: "Title of an error about a failed request for a route's line on the map.")
            case .searchResults:
                return OBALoc("error_report.title.search_results", value: "Couldn't load search results", comment: "Title of an error about a failed search.")
            case .serviceAlerts:
                return OBALoc("error_report.title.service_alerts", value: "Couldn't load service alerts", comment: "Title of an error about a failed request for transit service alerts.")
            case .bikeShare:
                return OBALoc("error_report.title.bike_share", value: "Couldn't load bike share", comment: "Title of an error about a failed request for bike and scooter share data.")
            case .unknown:
                return OBALoc("error_report.title.unknown", value: "Couldn't load this information", comment: "Title of an error about a failed request when the app can't tell what the request was for.")
            }
        }
    }

    // MARK: - Cause

    /// Why the request failed. One per row of the message catalog in the design.
    public enum Cause: String, Sendable, Equatable {
        case rateLimited
        case serverError
        case serverUnavailable
        case invalidResponseData
        case tripNotFound
        case stopNotFound
        case notFound
        case offline
        case cellularDataRestricted
        case captivePortal
        case noRegionSelected
        /// Not worth telling the rider about; see ``ErrorReport/isSilent``.
        case silent
        /// Not a failed request: an error that carries its own message, like
        /// `UnstructuredError("This stop is in a different region…")`. That
        /// message is shown as is.
        case message
        case fallback

        /// Whether the fix is on the rider's side (settings, network) rather than
        /// ours or the agency's. Drives the toast's icon.
        public var isRiderActionable: Bool {
            switch self {
            case .offline, .cellularDataRestricted, .captivePortal, .noRegionSelected: return true
            default: return false
            }
        }
    }

    /// What the toast's button does.
    public enum Action: Sendable, Equatable {
        /// Open the Problem Details page.
        case details
        /// Open the app's page in the Settings app.
        case openSettings
    }

    // MARK: - Properties

    public let cause: Cause

    /// Toast title and the headline of the Problem Details page.
    public let title: String

    /// One line under the toast title.
    public let summary: String

    /// The Problem Details page's longer explanation.
    public let explanation: String

    /// For support: the status code plus the error's case or type name, e.g.
    /// `429 Too Many Requests (rateLimited)` or `DecodingError.keyNotFound`.
    public let errorCode: String

    public let date: Date
    public let regionName: String?

    /// The failing request, with its query string and fragment stripped so the
    /// API key never ends up in a screenshot or a pasted report.
    public let requestURL: URL?

    public let appVersion: String
    public let systemVersion: String
    public let deviceModel: String

    /// A short code the rider can read out to support, e.g. `7F3K-Q2`. Also
    /// written to the log next to the error, so the two can be matched up.
    public let reference: String

    /// The button on the toast.
    public var action: Action {
        cause == .cellularDataRestricted ? .openSettings : .details
    }

    /// `true` when the error should not be shown to the rider at all.
    public var isSilent: Bool { cause == .silent }

    // MARK: - Init

    /// - Parameters:
    ///   - error: The error as thrown. Pass the *raw* error rather than the
    ///     output of ``ErrorClassifier/classify(_:regionName:isCellularDataRestricted:)``:
    ///     classification drops the response, and with it the request URL and
    ///     status code that support needs.
    ///   - regionName: The current region's name.
    ///   - isCellularDataRestricted: Whether cellular data is off for this app.
    public init(
        error: Error,
        regionName: String?,
        isCellularDataRestricted: Bool = false,
        date: Date = Date(),
        appVersion: String = Bundle.main.appVersion,
        systemVersion: String,
        deviceModel: String,
        reference: String = ErrorReport.makeReference()
    ) {
        let classified = ErrorClassifier.classify(error, regionName: regionName, isCellularDataRestricted: isCellularDataRestricted)
        let requestURL = Self.requestURL(from: error)
        let subject = Subject(url: requestURL)

        // Checked on the raw error: classification turns a cancellation into
        // `networkFailure` ("You're offline"), and an unreadable payload with no
        // region name into an `UnstructuredError` that would read as its own message.
        let ownMessage = Self.ownMessage(of: classified)
        if !Self.isCancellation(error), !Self.isUnreadablePayload(error), let message = ownMessage {
            self.cause = .message
            self.title = Strings.error
            self.summary = message
            self.explanation = message
        } else {
            let cause: Cause
            if Self.isCancellation(error) {
                cause = .silent
            } else if Self.isUnreadablePayload(error) {
                cause = .invalidResponseData
            } else {
                cause = Self.cause(for: classified, subject: subject)
            }
            self.cause = cause
            self.title = Self.title(for: cause, subject: subject)
            self.summary = Self.summary(for: cause, regionName: regionName)
            self.explanation = Self.explanation(for: cause, regionName: regionName)
        }
        self.errorCode = Self.errorCode(raw: error, classified: classified)
        self.date = date
        self.regionName = regionName
        self.requestURL = requestURL.map(Self.stripQuery)
        self.appVersion = appVersion
        self.systemVersion = systemVersion
        self.deviceModel = deviceModel
        self.reference = reference
    }

    // MARK: - Shared Text

    /// The text that Copy, Share, and Contact Support all use. The labels are
    /// English, since support reads them; the title and summary stay in the
    /// rider's language, matching the screen they saw.
    public var shareText: String {
        var lines = [
            "\(Bundle.main.appName) problem report",
            "\(title) — \(summary)",
            "Error: \(errorCode)",
            "Time: \(date.formatted(Date.ISO8601FormatStyle(timeZone: .current)))"
        ]
        if let regionName {
            lines.append("Region: \(regionName)")
        }
        if let requestURL {
            lines.append("Request: \(requestURL.absoluteString)")
        }
        lines.append("App: \(appSummary)")
        lines.append("Ref: \(reference)")
        return lines.joined(separator: "\n")
    }

    /// App version, iOS version, and device model on one line.
    public var appSummary: String {
        "\(appVersion) · iOS \(systemVersion) · \(deviceModel)"
    }

    /// The request as shown on the Problem Details page: no scheme, since it
    /// only costs width on a phone.
    public var displayRequest: String? {
        guard let requestURL else { return nil }
        let string = requestURL.absoluteString
        guard let scheme = requestURL.scheme else { return string }
        return String(string.dropFirst(scheme.count + 3))
    }

    // MARK: - Reference

    /// Six characters from an alphabet with no look-alikes (no 0/O, 1/I/L), so
    /// a rider can read it out over the phone.
    public static func makeReference() -> String {
        let alphabet = Array("23456789ABCDEFGHJKMNPQRSTUVWXYZ")
        let chars = (0..<6).map { _ in alphabet.randomElement()! }
        return String(chars[0..<4]) + "-" + String(chars[4..<6])
    }

    // MARK: - Private

    /// The message of an error that isn't about a request but brings its own
    /// rider-facing text. Decoding errors are excluded: theirs is developer prose.
    /// An `NSError` (MapKit, Core Location, …) counts when it was given an
    /// explicit description; the generic "The operation couldn't be completed"
    /// that Foundation makes up otherwise does not.
    private static func ownMessage(of classified: Error) -> String? {
        guard !(classified is APIError), !(classified is DecodingError) else { return nil }
        let description = (classified as? LocalizedError)?.errorDescription
            ?? (classified as NSError).userInfo[NSLocalizedDescriptionKey] as? String
        guard let description, !description.isEmpty else { return nil }
        return description
    }

    /// A request the app called off itself, not a failure worth a toast.
    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = innermostError(error) as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    /// A response that arrived but can't be read: a decoding failure, or the
    /// blank 200 that `APIService` reports as `requestNotFound`.
    private static func isUnreadablePayload(_ error: Error) -> Bool {
        if error is DecodingError { return true }
        if case .requestNotFound(let response) = error as? APIError, response.statusCode != 404 { return true }
        return false
    }

    private static func cause(for classified: Error, subject: Subject) -> Cause {
        guard let apiError = classified as? APIError else {
            return .fallback
        }

        switch apiError {
        case .rateLimited: return .rateLimited
        case .serverError: return .serverError
        case .serverUnavailable: return .serverUnavailable
        case .invalidResponseData, .invalidContentType, .noResponseBody: return .invalidResponseData
        case .requestNotFound:
            switch subject {
            case .livePosition: return .tripNotFound
            case .arrivalTimes: return .stopNotFound
            default: return .notFound
            }
        case .networkFailure: return .offline
        case .cellularDataRestricted: return .cellularDataRestricted
        case .captivePortal: return .captivePortal
        case .noRegionSelected: return .noRegionSelected
        case .surveyServiceNotConfigured: return .silent
        case .requestFailure: return .fallback
        }
    }

    private static func title(for cause: Cause, subject: Subject) -> String {
        switch cause {
        case .offline:
            return OBALoc("error_report.title.offline", value: "You're offline", comment: "Title of an error shown when the device has no internet connection.")
        case .cellularDataRestricted:
            let fmt = OBALoc("error_report.title.cellular_data_restricted_fmt", value: "Cellular data is off for %@", comment: "Title of an error shown when cellular data is turned off for this app in Settings. The substituted value is the app name.")
            return String(format: fmt, Bundle.main.appName)
        case .captivePortal:
            return OBALoc("error_report.title.captive_portal", value: "This Wi-Fi needs you to sign in", comment: "Title of an error shown when the Wi-Fi network requires the rider to sign in on a login page before it connects to the internet.")
        case .noRegionSelected:
            return OBALoc("error_report.title.no_region_selected", value: "Choose your region", comment: "Title of an error shown when no transit region has been selected.")
        default:
            return subject.title
        }
    }

    private static func summary(for cause: Cause, regionName: String?) -> String {
        switch cause {
        case .rateLimited:
            let fmt = OBALoc("error_report.summary.rate_limited_fmt", value: "%@ is busy.", comment: "One-line toast text: the server is getting too many requests. The substituted value is the app name.")
            return String(format: fmt, Bundle.main.appName)
        case .serverError:
            guard let regionName else { return fallbackSummary }
            let fmt = OBALoc("error_report.summary.server_error_fmt", value: "The %@ server hit a problem.", comment: "One-line toast text: the regional server returned an internal error. The substituted value is the region name, e.g. 'Puget Sound'.")
            return String(format: fmt, regionName)
        case .serverUnavailable:
            guard let regionName else { return fallbackSummary }
            let fmt = OBALoc("error_report.summary.server_unavailable_fmt", value: "Can't reach the %@ server.", comment: "One-line toast text: the regional server is down or unreachable. The substituted value is the region name, e.g. 'Puget Sound'.")
            return String(format: fmt, regionName)
        case .invalidResponseData:
            return OBALoc("error_report.summary.invalid_response_data", value: "The server sent data we can't read.", comment: "One-line toast text: the server answered with data the app can't read.")
        case .tripNotFound:
            return OBALoc("error_report.summary.trip_not_found", value: "This trip has ended.", comment: "One-line toast text: the trip has finished or was removed from today's service.")
        case .stopNotFound:
            return OBALoc("error_report.summary.stop_not_found", value: "This stop isn't in service.", comment: "One-line toast text: the agency no longer lists this stop.")
        case .notFound:
            return OBALoc("error_report.summary.not_found", value: "The server doesn't have it.", comment: "One-line toast text: the server has no record of the thing that was requested.")
        case .offline:
            return OBALoc("error_report.summary.offline", value: "Check your connection and try again.", comment: "One-line toast text: the device has no internet connection.")
        case .cellularDataRestricted:
            return OBALoc("error_report.summary.cellular_data_restricted", value: "Turn it on in Settings, or use Wi-Fi.", comment: "One-line toast text under a title saying cellular data is off for the app.")
        case .captivePortal:
            return OBALoc("error_report.summary.captive_portal", value: "Open the network's login page to continue.", comment: "One-line toast text under a title saying the Wi-Fi network needs the rider to sign in.")
        case .noRegionSelected:
            return OBALoc("error_report.summary.no_region_selected", value: "Choose your region to see transit info.", comment: "One-line toast text: no transit region has been selected.")
        case .silent, .message, .fallback:
            return fallbackSummary
        }
    }

    private static var fallbackSummary: String {
        OBALoc("error_report.summary.fallback", value: "Something went wrong.", comment: "One-line toast text for an error the app doesn't recognize.")
    }

    private static func explanation(for cause: Cause, regionName: String?) -> String {
        switch cause {
        case .rateLimited:
            let fmt = OBALoc("error_report.explanation.rate_limited_fmt", value: "%@ is getting more requests than it can handle right now. This usually clears up on its own within a minute.", comment: "Explanation of an error caused by the server being overloaded with requests (HTTP 429). The substituted value is the app name.")
            return String(format: fmt, Bundle.main.appName)
        case .serverError:
            guard let regionName else { return fallbackExplanation }
            let fmt = OBALoc("error_report.explanation.server_error_fmt", value: "The %@ server ran into a problem handling this request. It's still running, so trying again usually works.", comment: "Explanation of an internal server error. The substituted value is the region name, e.g. 'Puget Sound'.")
            return String(format: fmt, regionName)
        case .serverUnavailable:
            guard let regionName else { return fallbackExplanation }
            let fmt = OBALoc("error_report.explanation.server_unavailable_fmt", value: "The %@ server isn't responding. It may be down, or a VPN, firewall, or content blocker may be blocking it.", comment: "Explanation of an error where the regional server can't be reached. Mentions VPNs because riders often hit this on a filtered network. The substituted value is the region name, e.g. 'Puget Sound'.")
            return String(format: fmt, regionName)
        case .invalidResponseData:
            return OBALoc("error_report.explanation.invalid_response_data", value: "The server answered, but the data was incomplete or in a format we can't read. That's usually a problem with the agency's feed, not your phone.", comment: "Explanation of an error where the server's response couldn't be read.")
        case .tripNotFound:
            return OBALoc("error_report.explanation.trip_not_found", value: "This trip has finished its run or was removed from today's service, so there's no live position to show.", comment: "Explanation of an error where the server no longer has the requested trip.")
        case .stopNotFound:
            return OBALoc("error_report.explanation.stop_not_found", value: "The agency no longer lists this stop. It may have moved or closed.", comment: "Explanation of an error where the server no longer has the requested stop.")
        case .notFound:
            return OBALoc("error_report.explanation.not_found", value: "The server doesn't have what was requested. It may have been removed or renamed.", comment: "Explanation of a 404 Not Found error for something other than a stop or trip.")
        case .offline:
            return OBALoc("error_report.explanation.offline", value: "Your phone isn't connected to the internet. Information will update again when the connection returns.", comment: "Explanation of an error where the device has no internet connection.")
        case .cellularDataRestricted:
            let fmt = OBALoc("error_report.explanation.cellular_data_restricted_fmt", value: "%@ isn't allowed to use cellular data. Go to Settings › Cellular to turn it on, or connect to Wi-Fi.", comment: "Explanation of an error where cellular data is turned off for the app. The substituted value is the app name.")
            return String(format: fmt, Bundle.main.appName)
        case .captivePortal:
            return OBALoc("error_report.explanation.captive_portal", value: "The Wi-Fi network you're on needs you to sign in before it will connect to the internet. Sign in, or switch to cellular.", comment: "Explanation of an error where a Wi-Fi network requires signing in on a login page.")
        case .noRegionSelected:
            let fmt = OBALoc("error_report.explanation.no_region_selected_fmt", value: "%@ needs to know which transit region you're in.", comment: "Explanation of an error where no transit region is selected. The substituted value is the app name.")
            return String(format: fmt, Bundle.main.appName)
        case .silent, .message, .fallback:
            return fallbackExplanation
        }
    }

    private static var fallbackExplanation: String {
        OBALoc("error_report.explanation.fallback", value: "Something unexpected went wrong. It may be a temporary glitch. Try again, and if it keeps happening, send these details to support so we can fix it.", comment: "Explanation of an error the app doesn't recognize. 'These details' are the support details shown below it.")
    }

    // MARK: - Support Details

    /// Status code (when there is one) plus the case or type name.
    private static func errorCode(raw: Error, classified: Error) -> String {
        // A decoding failure is more useful by its own case than by the
        // `invalidResponseData` it classifies to.
        let name = raw is DecodingError ? caseName(raw) : caseName(classified)

        if let status = statusCode(from: raw) {
            guard let phrase = reasonPhrases[status] else {
                return "\(status) (\(name))"
            }
            return "\(status) \(phrase) (\(name))"
        }

        let nsError = innermostError(raw) as NSError
        if nsError.domain == NSURLErrorDomain {
            return "\(nsError.domain) \(nsError.code) (\(name))"
        }

        return name
    }

    /// Standard reason phrases for the codes OBA servers send. Foundation's
    /// `HTTPURLResponse.localizedString(forStatusCode:)` only has a generic
    /// "client error" for some of these, 429 among them.
    private static let reasonPhrases: [Int: String] = [
        400: "Bad Request",
        401: "Unauthorized",
        403: "Forbidden",
        404: "Not Found",
        408: "Request Timeout",
        410: "Gone",
        429: "Too Many Requests",
        500: "Internal Server Error",
        502: "Bad Gateway",
        503: "Service Unavailable",
        504: "Gateway Timeout"
    ]

    /// `rateLimited`, `DecodingError.keyNotFound`, or the bare type name.
    private static func caseName(_ error: Error) -> String {
        if let decodingError = error as? DecodingError {
            return "DecodingError." + enumCaseName(decodingError)
        }
        if error is APIError {
            return enumCaseName(error)
        }
        return String(describing: type(of: error))
    }

    /// The case name of an enum value. A case with a payload reflects as one
    /// child labeled with the case name; `String(describing:)` isn't reliable
    /// for that, since `DecodingError` describes itself in prose.
    private static func enumCaseName(_ value: Any) -> String {
        if let label = Mirror(reflecting: value).children.first?.label {
            return label
        }
        return String(describing: value)
    }

    private static func statusCode(from error: Error) -> Int? {
        guard let apiError = error as? APIError else { return nil }
        switch apiError {
        case .requestFailure(let response), .requestNotFound(let response):
            return response.statusCode
        case .rateLimited:
            return 429
        case .serverError:
            return 500
        case .serverUnavailable(_, let statusCode):
            return statusCode
        default:
            return nil
        }
    }

    private static func innermostError(_ error: Error) -> Error {
        if case .networkFailure(let inner?) = error as? APIError {
            return inner
        }
        return error
    }

    private static func requestURL(from error: Error) -> URL? {
        if let apiError = error as? APIError {
            switch apiError {
            case .requestFailure(let response), .requestNotFound(let response):
                return response.url
            case .networkFailure(let inner?):
                return requestURL(from: inner)
            default:
                return nil
            }
        }

        let nsError = error as NSError
        if let url = nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL {
            return url
        }
        if let string = nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String {
            return URL(string: string)
        }
        return nil
    }

    private static func stripQuery(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.query = nil
        components.fragment = nil
        return components.url ?? url
    }
}
