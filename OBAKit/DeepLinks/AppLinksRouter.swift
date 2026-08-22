//
//  AppLinksRouter.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// Creates deep links (i.e. Universal Links) to OBA-associated web pages.
public class AppLinksRouter: NSObject {
    private let application: Application

    /// Initializes the `AppLinksRouter`
    ///
    /// - Parameter application: The Application object
    public init?(application: Application) {
        self.application = application
    }

    /// The base URL for all operations in this object.
    private var baseURL: URL? {
        application.regionsService.currentRegion?.sidecarBaseURL
    }

    /// Creates a link to the OneBusAway stop page for the specified stop and region.
    ///
    /// - Parameters:
    ///   - stop: The stop for which a link will be created.
    ///   - region: The region in which the link will exist.
    public func url(for stop: Stop, region: Region) -> URL? {
        guard let baseURL else { return nil }

        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        components.path = String(format: "/regions/%d/stops/%@", region.regionIdentifier, stop.id)

        return components.url
    }

    private let deepLinkPathFormat = "/regions/%d/stops/%@/trips"
    private let deepLinkPattern = "/regions/(?<region>.*)/stops/(?<stop>.*)/trips"
    /// Stop pages are the same path without the `/trips` suffix. Named groups are
    /// `[^/]+` so a trip URL cannot masquerade as a stop whose ID contains `/trips`.
    private static let stopPathPattern = "/regions/(?<region>[^/]+)/stops/(?<stop>[^/]+)$"

    /// Encodes an `ArrivalDeparture` into an `URL` so that it can be shared as a deep link with others.
    /// - Parameters:
    ///   - arrivalDeparture: The object that will be encoded into a deep link URL.
    ///   - region: The region in which the `ArrivalDeparture` exists.
    ///   - destinationStopID: The stop where the passenger intends to exit. See: https://github.com/OneBusAway/onebusaway-ios/issues/449
    public func encode(arrivalDeparture: ArrivalDeparture, region: Region, destinationStopID: StopID? = nil) -> URL? {
        guard let baseURL else { return nil }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = String(format: deepLinkPathFormat, region.regionIdentifier, arrivalDeparture.stopID)

        var queryItems = [
            URLQueryItem(name: "trip_id", value: arrivalDeparture.tripID),
            URLQueryItem(name: "service_date", value: String(arrivalDeparture.serviceDate.timeIntervalSince1970)),
            URLQueryItem(name: "stop_sequence", value: String(arrivalDeparture.stopSequence))
        ]

        if let destinationStopID {
            queryItems.append(URLQueryItem(name: "destination_stop_id", value: destinationStopID))
        }

        components.queryItems = queryItems

        return components.url!
    }

    /// Converts `url` into an `ArrivalDepartureDeepLink` if `url` matches the required pattern.
    /// - Parameter url: The URL that will be converted into an `ArrivalDepartureDeepLink`
    ///
    /// The supplied URL must have this format: `"/regions/%d/stops/%@/trips"`
    /// It must also include the following query params: `trip_id`, `service_date`, `stop_sequence`.
    public func decode(url: URL?) -> ArrivalDepartureDeepLink? {
        guard
            let url = url,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        let path = components.path

        guard
            let matches = path.caseInsensitiveMatch(pattern: deepLinkPattern, namedGroups: ["stop", "region"]),
            let regionIDStr = matches["region"],
            let regionID = Int(regionIDStr),
            let stopID = matches["stop"],
            let tripID = components.queryItem(named: "trip_id")?.value,
            let serviceDateStr = components.queryItem(named: "service_date")?.value,
            let serviceDateScalar = TimeInterval(serviceDateStr),
            let stopSequenceStr = components.queryItem(named: "stop_sequence")?.value,
            let stopSequence = Int(stopSequenceStr)
        else {
            return nil
        }

        let title = components.queryItem(named: "title")?.value ?? "???"
        let serviceDate = Date(timeIntervalSince1970: serviceDateScalar)
        let vehicleID = components.queryItem(named: "vehicle_id")?.value
        let destinationStopID = components.queryItem(named: "destination_stop_id")?.value

        let deepLink = ArrivalDepartureDeepLink(
            title: title,
            regionID: regionID,
            stopID: stopID,
            tripID: tripID,
            serviceDate: serviceDate,
            stopSequence: stopSequence,
            vehicleID: vehicleID,
            destinationStopID: destinationStopID
        )

        return deepLink
    }

    // MARK: - Stop user activities

    /// The stop a donated `NSUserActivity` (or a stop webpage URL) should open.
    struct StopDestination: Equatable {
        let stopID: StopID
        let regionID: Int
    }

    /// Reads the stop out of a Siri/Shortcuts activity.
    ///
    /// Shortcuts round-trips `userInfo` through a plist, so `regionID` may arrive
    /// as `Int`, `NSNumber`, or `String`. When `userInfo` is stripped entirely,
    /// the donated `webpageURL` (`/regions/{id}/stops/{stopID}`) still names the
    /// stop. Trip URLs (`.../trips`) are not stops. See #1221.
    static func stopDestination(userInfo: [AnyHashable: Any]?, webpageURL: URL?) -> StopDestination? {
        if let userInfo,
           let stopID = userInfo[UserActivityBuilder.UserInfoKeys.stopID] as? StopID,
           let regionID = regionIdentifier(from: userInfo[UserActivityBuilder.UserInfoKeys.regionID]) {
            return StopDestination(stopID: stopID, regionID: regionID)
        }

        guard let webpageURL else { return nil }
        return stopDestination(fromWebpageURL: webpageURL)
    }

    static func stopDestination(fromWebpageURL url: URL) -> StopDestination? {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let matches = components.path.caseInsensitiveMatch(
                pattern: stopPathPattern,
                namedGroups: ["stop", "region"]
            ),
            let regionIDStr = matches["region"],
            let regionID = Int(regionIDStr),
            let stopID = matches["stop"],
            !stopID.isEmpty
        else {
            return nil
        }

        return StopDestination(stopID: stopID, regionID: regionID)
    }

    /// Plist round-trips turn `Int` into `NSNumber`; some Shortcuts builds
    /// stringify it. `as? Int` only covers the first two via bridging.
    private static func regionIdentifier(from value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    // MARK: - UI Routing

    /// Opens a stop by ID. The caller is responsible for stashing the ID when
    /// the UI or current region is not ready yet — this router does not fetch
    /// a `Stop` and then drop it on a nil `topViewController`.
    var showStopDestinationHandler: ((StopDestination) -> Void)?
    public var showArrivalDepartureDeepLink: ((ArrivalDepartureDeepLink) -> Void)?

    public func route(userActivity: NSUserActivity) -> Bool {
        Logger.info("AppLinksRouter.route: \(userActivity.activityType) - \(String(describing: userActivity.webpageURL))")

        if userActivity.activityType == NSUserActivityTypeBrowsingWeb {
            guard let url = userActivity.webpageURL else {
                return false
            }
            return route(url: url)
        }

        guard let userActivityBuilder = application.userActivityBuilder else {
            return false
        }

        switch userActivity.activityType {
        case userActivityBuilder.stopActivityType:
            return routeStop(userActivity: userActivity)
        case userActivityBuilder.tripActivityType:
            return routeTrip(userActivity: userActivity)
        default:
            return false
        }
    }

    private func route(url: URL) -> Bool {
        if let deepLink = decode(url: url) {
            showArrivalDepartureDeepLink?(deepLink)
            return true
        }

        if let destination = Self.stopDestination(fromWebpageURL: url) {
            showStopDestinationHandler?(destination)
            return true
        }

        return false
    }

    private func routeStop(userActivity: NSUserActivity) -> Bool {
        guard let destination = Self.stopDestination(
            userInfo: userActivity.userInfo,
            webpageURL: userActivity.webpageURL
        ) else {
            return false
        }

        showStopDestinationHandler?(destination)
        return true
    }

    private func routeTrip(userActivity: NSUserActivity) -> Bool {
        guard let url = userActivity.webpageURL else {
            return false
        }

        return route(url: url)
    }
}
