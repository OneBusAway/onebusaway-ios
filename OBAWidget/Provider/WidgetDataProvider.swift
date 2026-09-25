//  WidgetDataProvider.swift
//  OBAWidget
//
//  Created by Manu on 2024-10-15.
//

import Foundation
import OBAKitCore

/// What one fetch produced, ready to be sliced into timeline entries.
struct WidgetContent {
    let bookmarks: [Bookmark]
    let departures: [UUID: [ArrivalDeparture]]
    let fetchedAt: Date?

    static let empty = WidgetContent(bookmarks: [], departures: [:], fetchedAt: nil)
}

/// Loads the widget's bookmarks and their arrivals from the app-group suite.
///
/// Deliberately does **not** build a `CoreApplication`. That would start a
/// regions fetch, open and migrate the stop cache, and increment the launch
/// counter that survey gating reads — on every timeline reload, from an
/// extension. Everything the widget needs is in the suite: the bookmarks, the
/// client UUID, and the region the app resolved (`ResolvedRegionStore`), which
/// is also the only way an extension can see a custom region.
@MainActor
final class WidgetDataProvider {
    static let shared = WidgetDataProvider()

    private let userDefaults = UserDefaults(suiteName: Bundle.main.appGroup!)!

    /// Formatters for localization and styling.
    let formatters = Formatters(
        locale: Locale.autoupdatingCurrent,
        calendar: Calendar.autoupdatingCurrent,
        themeColors: ThemeColors.shared
    )

    /// Favorited bookmarks in `region`, in stored order.
    private func bookmarks(in region: Region) -> [Bookmark] {
        UserDefaultsStore(userDefaults: userDefaults).favoritedBookmarks
            .filter { $0.regionIdentifier == region.regionIdentifier }
    }

    /// - Parameter maximumBookmarks: How many bookmarks the widget can show
    ///   (`BookmarkEntry.maximumBookmarks(for:)`). Fetching more is wasted
    ///   network on every reload, and reloads now run up to 48 times a day.
    func load(maximumBookmarks: Int) async -> WidgetContent {
        let store = ResolvedRegionStore(userDefaults: userDefaults)
        guard let region = store.region(bundledRegionsFilePath: Bundle.main.path(forResource: "regions", ofType: "json")) else {
            Logger.error("Widget: no region available.")
            return .empty
        }

        let bookmarks = Array(bookmarks(in: region).prefix(maximumBookmarks))
        guard !bookmarks.isEmpty else {
            Logger.info("Widget: no bookmarks to load data for.")
            return .empty
        }

        guard let apiKey = Bundle.main.restServerAPIKey else {
            Logger.error("Widget: no REST API key in the extension's Info.plist.")
            return WidgetContent(bookmarks: bookmarks, departures: [:], fetchedAt: nil)
        }

        let service = RESTAPIService.standalone(
            region: region,
            apiKey: apiKey,
            appVersion: Bundle.main.appVersion,
            uuid: UserUUID.value(in: userDefaults)
        )

        // 90, not the default 60: entries run up to 30 minutes past the fetch,
        // so every one of them still knows a full hour ahead — which is what a
        // row's "no departures in the next 60 minutes" fallback claims.
        let departures = await BookmarkArrivalsLoader(minutesAfter: 90).departuresByBookmark(for: bookmarks, using: service)
        return WidgetContent(bookmarks: bookmarks, departures: departures, fetchedAt: departures.isEmpty ? nil : Date())
    }
}
