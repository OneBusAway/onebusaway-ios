//  WidgetDataProvider.swift
//  OBAWidget
//
//  Created by Manu on 2024-10-15.
//

import Foundation
import OBAKitCore
import WidgetKit

/// What one fetch produced, ready to be sliced into timeline entries.
struct WidgetContent {
    let bookmarks: [Bookmark]
    let departures: [UUID: [ArrivalDeparture]]
    let fetchedAt: Date?
    /// Offline only: see `SavedBookmarkDepartures`.
    var scheduledDepartures: [UUID: [ScheduledDeparture]] = [:]
    var savedAt: Date?
    var currentPage: Int = 0
    var totalPages: Int = 0

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

    let userDefaults = UserDefaults(suiteName: Bundle.main.appGroup!)!

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

    /// Total favorited bookmarks in the currently resolved region.
    func currentRegionBookmarkCount() -> Int {
        let store = ResolvedRegionStore(userDefaults: userDefaults)
        guard let region = store.region(bundledRegionsFilePath: Bundle.main.path(forResource: "regions", ofType: "json")) else {
            return 0
        }
        return bookmarks(in: region).count
    }

    private struct BookmarkSlice {
        let bookmarks: [Bookmark]
        let currentPage: Int
        let totalPages: Int
    }

    private func visibleBookmarkSlice(
        from allBookmarks: [Bookmark],
        for family: WidgetFamily
    ) -> BookmarkSlice {
        if family == .systemMedium {
            let paginator = WidgetBookmarkPaginator(userDefaults: userDefaults)
            let totalPages = WidgetBookmarkPaginator.totalPages(bookmarkCount: allBookmarks.count)
            let currentPage = paginator.currentPage(bookmarkCount: allBookmarks.count)
            let visible = WidgetBookmarkPaginator.pageSlice(bookmarks: allBookmarks, pageIndex: currentPage)
            return BookmarkSlice(bookmarks: visible, currentPage: currentPage, totalPages: totalPages)
        }

        let visible = Array(allBookmarks.prefix(BookmarkEntry.maximumBookmarks(for: family)))
        return BookmarkSlice(bookmarks: visible, currentPage: 0, totalPages: 1)
    }

    /// Loads visible bookmarks for `family` (paginated for `.systemMedium`, capped
    /// at `maximumBookmarks` for `.systemLarge`) and fetches departures only for
    /// the visible rows so off-page stops never cost extra network requests.
    func load(for family: WidgetFamily) async -> WidgetContent {
        let store = ResolvedRegionStore(userDefaults: userDefaults)
        guard let region = store.region(bundledRegionsFilePath: Bundle.main.path(forResource: "regions", ofType: "json")) else {
            Logger.error("Widget: no region available.")
            return .empty
        }

        let allBookmarks = bookmarks(in: region)
        guard !allBookmarks.isEmpty else {
            Logger.info("Widget: no bookmarks to load data for.")
            return .empty
        }

        let slice = visibleBookmarkSlice(from: allBookmarks, for: family)

        guard let apiKey = Bundle.main.restServerAPIKey else {
            Logger.error("Widget: no REST API key in the extension's Info.plist.")
            return WidgetContent(
                bookmarks: slice.bookmarks,
                departures: [:],
                fetchedAt: nil,
                currentPage: slice.currentPage,
                totalPages: slice.totalPages
            )
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
        //
        // `.appDefault` resolves to the extension's own Caches, not the app's,
        // which an extension can't read. So the widget keeps its own copy,
        // saved on its own fetches, and shows it when it can't reach the server.
        let loaded = await BookmarkArrivalsLoader(minutesAfter: 90, savedArrivals: .appDefault)
            .departuresByBookmarkKeepingSaved(for: slice.bookmarks, using: service)
        return WidgetContent(
            bookmarks: slice.bookmarks,
            departures: loaded.departures,
            fetchedAt: loaded.departures.isEmpty ? nil : Date(),
            scheduledDepartures: loaded.scheduledDepartures,
            savedAt: loaded.savedAt,
            currentPage: slice.currentPage,
            totalPages: slice.totalPages
        )
    }
}
