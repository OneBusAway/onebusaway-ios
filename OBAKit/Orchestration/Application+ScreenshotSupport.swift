//
//  Application+ScreenshotSupport.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

#if DEBUG
import ActivityKit
import OBAKitCore
import UIKit

/// DEBUG-only launch hooks that put the app into the state an App Store
/// screenshot needs. `AppStoreScreenshotUITests` sets them through the launch
/// environment; see `docs/app-store/README.md`.
///
/// - `SCREENSHOT_STOP_ID`: opens this stop's sheet over the map on launch.
/// - `SCREENSHOT_BOOKMARKS`: a JSON array of `ScreenshotBookmarkSeed`. Replaces
///   every bookmark and group with trip bookmarks built from live arrivals, so
///   the Bookmarks tab shows real countdowns.
/// - `SCREENSHOT_END_LIVE_ACTIVITIES=1`: ends every Live Activity, so the
///   Lock Screen slide's activity is gone from the Dynamic Island when a later
///   slide shows another app.
extension Application {

    struct ScreenshotBookmarkSeed: Decodable {
        let group: String
        let name: String
        let stopID: StopID
        let routeID: RouteID
    }

    func applyScreenshotLaunchHooks() {
        let environment = ProcessInfo.processInfo.environment

        if let stopID = environment["SCREENSHOT_STOP_ID"] {
            Task { await showScreenshotStop(stopID) }
        }

        if environment["SCREENSHOT_END_LIVE_ACTIVITIES"] == "1" {
            Task {
                for activity in Activity<TripAttributes>.activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
        }

        if let json = environment["SCREENSHOT_BOOKMARKS"] {
            do {
                let seeds = try JSONDecoder().decode([ScreenshotBookmarkSeed].self, from: Data(json.utf8))
                Task { await seedScreenshotBookmarks(seeds) }
            } catch {
                Logger.error("Screenshot bookmarks: undecodable SCREENSHOT_BOOKMARKS: \(error)")
            }
        }
    }

    /// Opens the stop the way a tap on its map pin does: as the map's half-height
    /// sheet, with the map still showing above it. (`pendingStopID` pushes a
    /// full-screen Stop page instead.)
    private func showScreenshotStop(_ stopID: StopID) async {
        for _ in 0..<60 {
            if currentRegion != nil,
               let root = delegate?.uiApplication?.keyWindowFromScene?.rootViewController,
               let map = Self.firstMapViewController(in: root) {
                // Let the map settle on the rider's location before the sheet covers it.
                try? await Task.sleep(for: .seconds(2))
                map.show(stopID: stopID)
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        Logger.error("Screenshot stop: no map after 30 seconds.")
    }

    private static func firstMapViewController(in controller: UIViewController) -> MapViewController? {
        if let map = controller as? MapViewController {
            return map
        }
        for child in controller.children {
            if let map = firstMapViewController(in: child) {
                return map
            }
        }
        return nil
    }

    private func seedScreenshotBookmarks(_ seeds: [ScreenshotBookmarkSeed]) async {
        // The region and its API service load asynchronously on launch.
        for _ in 0..<60 where apiService == nil || currentRegion == nil {
            try? await Task.sleep(for: .milliseconds(500))
        }
        guard let apiService, let regionID = currentRegion?.regionIdentifier else {
            Logger.error("Screenshot bookmarks: no region after 30 seconds.")
            return
        }

        for bookmark in userDataStore.bookmarks {
            userDataStore.delete(bookmark: bookmark)
        }
        for group in userDataStore.bookmarkGroups {
            userDataStore.deleteGroup(group)
        }

        var groups = [String: BookmarkGroup]()
        for seed in seeds {
            let arrivals: StopArrivals
            do {
                arrivals = try await apiService.getArrivalsAndDeparturesForStop(id: seed.stopID, minutesBefore: 0, minutesAfter: 90).entry
            } catch {
                Logger.error("Screenshot bookmarks: arrivals for \(seed.stopID) failed: \(error)")
                continue
            }
            guard let arrivalDeparture = arrivals.arrivalsAndDepartures.first(where: { $0.routeID == seed.routeID }) else {
                Logger.error("Screenshot bookmarks: no \(seed.routeID) departures at \(seed.stopID).")
                continue
            }

            let group: BookmarkGroup
            if let existing = groups[seed.group] {
                group = existing
            } else {
                group = BookmarkGroup(name: seed.group, sortOrder: groups.count)
                userDataStore.upsert(bookmarkGroup: group)
                groups[seed.group] = group
            }

            let bookmark = Bookmark(name: seed.name, regionIdentifier: regionID, arrivalDeparture: arrivalDeparture)
            userDataStore.add(bookmark, to: group, index: Int.max)
        }
    }
}
#endif // DEBUG
