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

    /// Favorited bookmarks in `region`, in the user's order.
    private func bookmarks(in region: Region) -> [Bookmark] {
        UserDefaultsStore(userDefaults: userDefaults).favoritedBookmarks
            .filter { $0.regionIdentifier == region.regionIdentifier }
    }

    func load() async -> WidgetContent {
        let store = ResolvedRegionStore(userDefaults: userDefaults)
        guard let region = store.region(bundledRegionsFilePath: Bundle.main.path(forResource: "regions", ofType: "json")) else {
            Logger.error("Widget: no region available.")
            return .empty
        }

        let bookmarks = bookmarks(in: region)
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

        let departures = await BookmarkArrivalsLoader().departuresByBookmark(for: bookmarks, using: service)
        return WidgetContent(bookmarks: bookmarks, departures: departures, fetchedAt: departures.isEmpty ? nil : Date())
    }
}
