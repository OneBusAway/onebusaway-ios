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
/// environment; `docs/app-store/README.md` lists them.
///
/// `init` only reads them. The work waits for the app's own readiness points,
/// the same way `pendingRentalsCoordinate` does: the map claims the stop when it
/// appears or the region loads, and the bookmarks are seeded once the root UI
/// or the region is in place.
struct ScreenshotBookmarkSeed: Decodable {
    let group: String
    let name: String
    let stopID: StopID
    let routeID: RouteID
}

extension Application {

    func applyScreenshotLaunchHooks() {
        let environment = ProcessInfo.processInfo.environment

        screenshotStopID = environment["TEST_SCREENSHOT_STOP_ID"]

        if let json = environment["TEST_SCREENSHOT_BOOKMARKS"] {
            do {
                screenshotBookmarkSeeds = try JSONDecoder().decode([ScreenshotBookmarkSeed].self, from: Data(json.utf8))
            } catch {
                Logger.error("Screenshot bookmarks: undecodable TEST_SCREENSHOT_BOOKMARKS: \(error)")
            }
        }

        if environment["TEST_SCREENSHOT_END_LIVE_ACTIVITIES"] == "1" {
            Task {
                for activity in Activity<TripAttributes>.activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
        }
    }

    /// The stop to open as the map's sheet, once there is a region to load it
    /// from. Cleared on return, so it opens once.
    func claimScreenshotStop() -> StopID? {
        guard currentRegion != nil, let stopID = screenshotStopID else { return nil }
        screenshotStopID = nil
        return stopID
    }

    /// Replaces every bookmark and group with trip bookmarks built from live
    /// arrivals, so the Bookmarks tab shows real countdowns. Runs once, as soon
    /// as there is an API service to fetch them from.
    func seedScreenshotBookmarksIfNeeded() {
        guard let seeds = screenshotBookmarkSeeds,
              let apiService,
              let regionID = currentRegion?.regionIdentifier else {
            return
        }
        screenshotBookmarkSeeds = nil

        for bookmark in userDataStore.bookmarks {
            userDataStore.delete(bookmark: bookmark)
        }
        for group in userDataStore.bookmarkGroups {
            userDataStore.deleteGroup(group)
        }

        Task {
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

                // `add(_:to:)` upserts the group and appends the bookmark to it.
                let group = groups[seed.group] ?? BookmarkGroup(name: seed.group, sortOrder: groups.count)
                groups[seed.group] = group

                let bookmark = Bookmark(name: seed.name, regionIdentifier: regionID, arrivalDeparture: arrivalDeparture)
                userDataStore.add(bookmark, to: group)
            }
        }
    }
}

extension MapViewController {
    /// Opens the screenshot stop the way a tap on its pin does: as the map's
    /// half-height sheet, with the map still showing above it. (`pendingStopID`
    /// pushes a full-screen Stop page instead.)
    func showScreenshotStopIfNeeded() {
        guard viewIfLoaded?.window != nil, let stopID = application.claimScreenshotStop() else { return }
        show(stopID: stopID)
    }
}
#endif // DEBUG
