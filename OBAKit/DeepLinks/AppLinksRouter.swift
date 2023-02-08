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
    private let baseURL: URL
    private let application: Application

    /// Initializes the `AppLinksRouter`
    ///
    /// - Parameter baseURL: The deep link server host. Usually this is `http://alerts.onebusaway.org`.
    public init?(baseURL: URL?, application: Application) {
        guard let baseURL = baseURL else {
            return nil
        }

        self.baseURL = baseURL
        self.application = application
    }

    /// Creates a link to the OneBusAway stop page for the specified stop and region.
    ///
    /// - Parameters:
    ///   - stop: The stop for which a link will be created.
    ///   - region: The region in which the link will exist.
    public func url(for stop: Stop, region: Region) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        components.path = String(format: "/regions/%d/stops/%@", region.regionIdentifier, stop.id)

        return components.url
    }

    private let deepLinkPathFormat = "/regions/%d/stops/%@/trips"
    private let deepLinkPattern = "/regions/(?<region>.*)/stops/(?<stop>.*)/trips"

    /// Encodes an `ArrivalDeparture` into an `URL` so that it can be shared as a deep link with others.
    /// - Parameters:
    ///   - arrivalDeparture: The object that will be encoded into a deep link URL.
    ///   - region: The region in which the `ArrivalDeparture` exists.
    public func encode(arrivalDeparture: ArrivalDeparture, region: Region) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = String(format: deepLinkPathFormat, region.regionIdentifier, arrivalDeparture.stopID)
        components.queryItems = [
            URLQueryItem(name: "trip_id", value: arrivalDeparture.tripID),
            URLQueryItem(name: "service_date", value: String(arrivalDeparture.serviceDate.timeIntervalSince1970)),
            URLQueryItem(name: "stop_sequence", value: String(arrivalDeparture.stopSequence))
        ]

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

        let deepLink = ArrivalDepartureDeepLink(title: title, regionID: regionID, stopID: stopID, tripID: tripID, serviceDate: serviceDate, stopSequence: stopSequence, vehicleID: vehicleID)

        return deepLink
    }

    // MARK: - UI Routing

    public var showStopHandler: ((Stop) -> Void)?
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
        guard let deepLink = decode(url: url) else {
            return false
        }

        showArrivalDepartureDeepLink?(deepLink)

        return true
    }

    private func routeStop(userActivity: NSUserActivity) -> Bool {
        guard
            let userInfo = userActivity.userInfo,
            let stopID = userInfo[UserActivityBuilder.UserInfoKeys.stopID] as? StopID,
            let regionID = userInfo[UserActivityBuilder.UserInfoKeys.regionID] as? Int,
            let apiService = application.apiService,
            application.currentRegion?.regionIdentifier == regionID
            else {
                return false
        }

        Task(priority: .userInitiated) {
            do {
                let stop = try await apiService.getStop(id: stopID)
                await MainActor.run {
                    self.showStopHandler?(stop.entry)
                }
            } catch {
                await self.application.displayError(error)
            }
        }

        return true
    }

    private func routeTrip(userActivity: NSUserActivity) -> Bool {
        guard let url = userActivity.webpageURL else {
            return false
        }

        return route(url: url)
    }
}
