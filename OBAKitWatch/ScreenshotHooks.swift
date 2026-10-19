//
//  ScreenshotHooks.swift
//  OBAKitWatch
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

#if DEBUG
import SwiftUI
import OBAKitCore

/// DEBUG-only launch hooks that put the watch app into the state an App Store
/// screenshot needs. `scripts/app_store_screenshots --watch` sets them through
/// the launch environment; `docs/app-store/README.md` lists them.
///
/// - `TEST_SCREENSHOT_TAB`: `bookmarks` or `nearby`, the tab to show.
/// - `TEST_SCREENSHOT_BOOKMARKS`: replaces the bookmarks synced from the phone
///   with trip bookmarks built from live arrivals (see `ScreenshotBookmarkSeed`).
/// - `TEST_SCREENSHOT_STOP_ID`: opens that seeded bookmark's stop.
/// - `TEST_SCREENSHOT_ROUTE_ID`: opens that route's Nearby card once it loads.
struct ScreenshotHooks: ViewModifier {
    @Environment(WatchAppHost.self) private var host
    @Binding var tab: WatchRootView.Tab
    @Binding var bookmarksPath: NavigationPath
    @Binding var nearbyPath: NavigationPath
    let nearby: NearbyRoutesModel?

    // Each is cleared once applied, so it happens once.
    @State private var seeds = ScreenshotBookmarkSeed.fromEnvironment()
    @State private var stopID = ProcessInfo.processInfo.environment["TEST_SCREENSHOT_STOP_ID"]
    @State private var routeID = ProcessInfo.processInfo.environment["TEST_SCREENSHOT_ROUTE_ID"]

    func body(content: Content) -> some View {
        content
            .onAppear {
                if ProcessInfo.processInfo.environment["TEST_SCREENSHOT_TAB"] == "nearby" {
                    tab = .nearby
                }
            }
            // The seed needs a region to fetch arrivals from, which can land
            // after launch.
            .task(id: host.currentRegion?.regionIdentifier) {
                await seedBookmarks()
            }
            .onChange(of: nearby?.directions) { _, directions in
                guard let routeID, let direction = directions?.first(where: { $0.key.routeID == routeID }) else { return }
                self.routeID = nil
                nearbyPath.append(direction.key)
            }
    }

    private func seedBookmarks() async {
        guard let seeds, let apiService = host.apiService, let region = host.currentRegion else { return }
        self.seeds = nil

        var groups = [String: WatchBookmarkGroup]()
        var bookmarks = [WatchBookmark]()
        for seed in seeds {
            guard let bookmark = await seed.makeBookmark(apiService: apiService, regionIdentifier: region.regionIdentifier) else {
                continue
            }
            let group = groups[seed.group] ?? WatchBookmarkGroup(id: UUID(), name: seed.group)
            groups[seed.group] = group
            bookmark.groupID = group.id
            bookmarks.append(WatchBookmark(bookmark: bookmark))
        }

        do {
            // Groups in the order the seeds name them.
            let orderedGroups = seeds.map(\.group).reduce(into: [WatchBookmarkGroup]()) { ordered, name in
                if let group = groups[name], !ordered.contains(group) { ordered.append(group) }
            }
            host.bookmarkStore.update(payload: try WatchSyncPayload(bookmarks: bookmarks, groups: orderedGroups, region: region))
        } catch {
            Logger.error("Screenshot bookmarks: couldn't build the payload: \(error)")
            return
        }

        if let stopID, let bookmark = bookmarks.first(where: { $0.stopID == stopID }) {
            self.stopID = nil
            bookmarksPath.append(bookmark.stop)
        }
    }
}
#endif // DEBUG
