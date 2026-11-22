//
//  Strings+Sheet.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// Localized strings consumed by the SwiftUI sheet surfaces
/// (`MapPanelRootView` and its views) and related UIKit components.
public extension Strings {

    // MARK: - Routes on Map

    static let routesOnMapTitle = OBALoc(
        "map_sheet.routes_on_map",
        value: "Routes on Map",
        comment: "Map sheet row, and the title of the screen it opens, listing the routes that serve the stops currently loaded on the map."
    )

    static let routesOnMapFooter = OBALoc(
        "map_sheet.routes_on_map_footer",
        value: "Show only one route's path and stops. Close the route to see every stop again.",
        comment: "Footer under the Routes on Map row explaining what picking a route does and how to undo it."
    )

    static let routesOnMapEmpty = OBALoc(
        "map_sheet.routes_on_map_empty",
        value: "No routes on this part of the map",
        comment: "Empty state on the Routes on Map screen when no stops with routes are loaded for the visible map area."
    )

    static let routesOnMapZoomedOut = OBALoc(
        "map_sheet.routes_on_map_zoomed_out",
        value: "Zoom in to see the routes serving this area",
        comment: "Empty state on the Routes on Map screen when the map is zoomed out too far to load stops."
    )

    static let routesOnMapRowHint = OBALoc(
        "map_sheet.routes_on_map_row_hint",
        value: "Shows only this route on the map.",
        comment: "VoiceOver hint on a route row in the Routes on Map list."
    )

    // MARK: - Shared Section Titles

    // nonisolated: OBAKit defaults to @MainActor isolation. These constants are accessed from nonisolated
    // contexts (e.g., `NearbyStopsListViewController.Section`, which is `nonisolated`), so they must be
    // explicitly marked to remain reachable.
    nonisolated static let explore = OBALoc(
        "home_sheet.explore.title",
        value: "Explore",
        comment: "Header of a section on the map panel's home sheet that holds shortcuts to other features: the trip planner, bikes and scooters on the map, and alarms."
    )

    static let settingsAndMore = OBALoc(
        "home_sheet.settings.title",
        value: "Settings and More",
        comment: "Header of the last section on the map panel's home sheet, which holds rows for map display options, app settings, and the More screen."
    )

    nonisolated static let nearbyStops = OBALoc(
        "nearby_stops_controller.title",
        value: "Nearby Stops",
        comment: "The title of the Nearby Stops controller."
    )

    nonisolated static let bookmarks = OBALoc(
        "search_controller.bookmarks.header",
        value: "Bookmarks",
        comment: "Title of the Bookmarks search header"
    )

    // MARK: - Tabs

    // The classic tab bar's titles, shared with the map panel's home tabs
    // (`HomeTab`) so each key has one definition.

    static let recentTabTitle = OBALoc(
        "recent_stops_controller.title",
        value: "Recent",
        comment: "The title of the Recent Stops controller."
    )

    static let bookmarksTabTitle = OBALoc(
        "bookmarks_controller.title",
        value: "Bookmarks",
        comment: "Title of the Bookmarks tab"
    )

    static let moreTabTitle = OBALoc(
        "more_controller.title",
        value: "More",
        comment: "Title of the More tab / accessibility label for the map-panel more button."
    )
}
