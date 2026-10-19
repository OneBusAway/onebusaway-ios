//
//  ScreenshotBookmarkSeed.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

#if DEBUG
import Foundation

/// A trip bookmark for the App Store screenshots, decoded from the
/// `TEST_SCREENSHOT_BOOKMARKS` launch environment variable (a JSON array) that
/// the iOS and watch apps' DEBUG screenshot hooks read. See
/// `docs/app-store/README.md`.
public struct ScreenshotBookmarkSeed: Decodable, Sendable {
    public let group: String
    public let name: String
    public let stopID: StopID
    public let routeID: RouteID

    /// The seeds in `TEST_SCREENSHOT_BOOKMARKS`, or nil when it's unset or
    /// undecodable.
    public static func fromEnvironment() -> [ScreenshotBookmarkSeed]? {
        guard let json = ProcessInfo.processInfo.environment["TEST_SCREENSHOT_BOOKMARKS"] else { return nil }
        do {
            return try JSONDecoder().decode([ScreenshotBookmarkSeed].self, from: Data(json.utf8))
        } catch {
            Logger.error("Screenshot bookmarks: undecodable TEST_SCREENSHOT_BOOKMARKS: \(error)")
            return nil
        }
    }

    /// A trip bookmark on the route's next departure from the stop, so it
    /// shows real countdowns; nil when the route has none in the next 90
    /// minutes or the fetch fails.
    public func makeBookmark(apiService: RESTAPIService, regionIdentifier: Int) async -> Bookmark? {
        let arrivals: StopArrivals
        do {
            arrivals = try await apiService.getArrivalsAndDeparturesForStop(id: stopID, minutesBefore: 0, minutesAfter: 90).entry
        } catch {
            Logger.error("Screenshot bookmarks: arrivals for \(stopID) failed: \(error)")
            return nil
        }
        guard let arrivalDeparture = arrivals.arrivalsAndDepartures.first(where: { $0.routeID == routeID }) else {
            Logger.error("Screenshot bookmarks: no \(routeID) departures at \(stopID).")
            return nil
        }
        return Bookmark(name: name, regionIdentifier: regionIdentifier, arrivalDeparture: arrivalDeparture)
    }
}
#endif // DEBUG
