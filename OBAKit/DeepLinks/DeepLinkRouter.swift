//
//  DeepLinkRouter.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 5/31/19.
//

import Foundation
import OBAKitCore
import CocoaLumberjackSwift

/// Creates deep links (i.e. Universal Links) to OBA-associated web pages.
public class DeepLinkRouter: NSObject {
    private let baseURL: URL
    private let application: Application

    /// Initializes the `DeepLinkRouter`
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

        let title = components.queryItem(named: "title")?.value ?? "ABXOXO TODO TITLE FOR TRIP DEEP LINK"
        let serviceDate = Date(timeIntervalSince1970: serviceDateScalar)
        let vehicleID = components.queryItem(named: "vehicle_id")?.value

        let deepLink = ArrivalDepartureDeepLink(title: title, regionID: regionID, stopID: stopID, tripID: tripID, serviceDate: serviceDate, stopSequence: stopSequence, vehicleID: vehicleID)

        return deepLink
    }

    // MARK: - UI Routing

    public var showStopHandler: ((Stop) -> Void)?
    public var showArrivalDepartureDeepLink: ((ArrivalDepartureDeepLink) -> Void)?

    public func route(userActivity: NSUserActivity) -> Bool {
        DDLogInfo("DeepLinkRouter.route: \(userActivity.activityType) - \(String(describing: userActivity.webpageURL))")

        switch userActivity.activityType {
        case NSUserActivityTypeBrowsingWeb:
            guard let url = userActivity.webpageURL else {
                return false
            }
            return route(url: url)
        case application.userActivityBuilder.stopActivityType:
            return routeStop(userActivity: userActivity)
        case application.userActivityBuilder.tripActivityType:
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
            let stopID = userInfo[UserActivityBuilder.UserInfoKeys.stopID] as? String,
            let regionID = userInfo[UserActivityBuilder.UserInfoKeys.regionID] as? Int,
            let modelService = application.restAPIModelService,
            application.currentRegion?.regionIdentifier == regionID
            else {
                return false
        }

        let op = modelService.getStop(id: stopID)
        op.then { [weak self] in
            guard
                let self = self,
                let stop = op.stops.first
                else { return }

            self.showStopHandler?(stop)
        }

        return true
    }

    private func routeTrip(userActivity: NSUserActivity) -> Bool {
        guard let userInfo = userActivity.userInfo else {
            return false
        }
        print("🎉 abxoxo - trip activity: \(userInfo)")
        return true
    }
}
