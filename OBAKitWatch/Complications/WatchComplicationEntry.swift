//
//  WatchComplicationEntry.swift
//  OBAKitWatch
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore
import WidgetKit

/// Timeline entry for watchOS next-departure complications and Smart Stack cards.
nonisolated public struct WatchComplicationEntry: TimelineEntry, Sendable {
    public let date: Date
    public let state: NextDepartureComplicationState
    public let fetchedAt: Date?

    public init(
        date: Date,
        state: NextDepartureComplicationState,
        fetchedAt: Date? = nil
    ) {
        self.date = date
        self.state = state
        self.fetchedAt = fetchedAt
    }

    /// Maximum bookmarks fetched for a watch complication family.
    public static func maximumBookmarks(for family: WidgetFamily) -> Int {
        switch family {
        case .accessoryCircular:
            return WidgetBookmarkFamily.accessoryCircular.maximumBookmarks
        case .accessoryRectangular:
            return WidgetBookmarkFamily.accessoryRectangular.maximumBookmarks
        case .accessoryInline:
            return WidgetBookmarkFamily.accessoryInline.maximumBookmarks
        case .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge, .systemExtraLargePortrait, .accessoryCorner:
            return WidgetBookmarkFamily.accessoryCircular.maximumBookmarks
        @unknown default:
            return WidgetBookmarkFamily.accessoryCircular.maximumBookmarks
        }
    }
}

/// Snapshot of data loaded for a watch complication timeline reload.
nonisolated public struct WatchComplicationContent: Sendable {
    public let bookmark: WatchBookmark?
    public let departures: [UUID: [ArrivalDeparture]]
    public let fetchedAt: Date?

    public static let empty = WatchComplicationContent(bookmark: nil, departures: [:], fetchedAt: nil)

    public init(bookmark: WatchBookmark?, departures: [UUID: [ArrivalDeparture]], fetchedAt: Date?) {
        self.bookmark = bookmark
        self.departures = departures
        self.fetchedAt = fetchedAt
    }
}

/// Stateless loader for watchOS complications. Reads synced bookmarks and the
/// resolved region from the app-group `UserDefaults` suite without building a
/// `CoreApplication`.
@MainActor
public final class WatchComplicationDataLoader {
    private let userDefaults: UserDefaults?
    private let bundledRegionsFilePath: String?
    private let restServerAPIKey: String?
    private let appVersion: String
    private let dataLoader: URLDataLoader

    public let formatters = Formatters(
        locale: .autoupdatingCurrent,
        calendar: .autoupdatingCurrent,
        themeColors: .shared
    )

    public init(
        userDefaults: UserDefaults?,
        bundledRegionsFilePath: String?,
        restServerAPIKey: String?,
        appVersion: String,
        dataLoader: URLDataLoader = URLSession.shared
    ) {
        self.userDefaults = userDefaults
        self.bundledRegionsFilePath = bundledRegionsFilePath
        self.restServerAPIKey = restServerAPIKey
        self.appVersion = appVersion
        self.dataLoader = dataLoader
    }

    public static func fromMainBundle(dataLoader: URLDataLoader = URLSession.shared) -> WatchComplicationDataLoader {
        let bundle = Bundle.main
        let userDefaults = bundle.appGroup.flatMap { UserDefaults(suiteName: $0) }
        return WatchComplicationDataLoader(
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundle.bundledRegionsFilePath,
            restServerAPIKey: bundle.restServerAPIKey,
            appVersion: bundle.appVersion,
            dataLoader: dataLoader
        )
    }

    public func load(maximumBookmarks: Int = 1) async -> WatchComplicationContent {
        guard let userDefaults else {
            Logger.error("WatchComplication: no app-group UserDefaults available.")
            return .empty
        }

        let bookmarkStore = WatchBookmarkStore(userDefaults: userDefaults)
        guard !bookmarkStore.bookmarks.isEmpty else {
            Logger.info("WatchComplication: no bookmarks to load data for.")
            return .empty
        }

        let regionStore = ResolvedRegionStore(userDefaults: userDefaults)
        guard let region = regionStore.region(bundledRegionsFilePath: bundledRegionsFilePath) ?? bookmarkStore.syncedRegion else {
            Logger.error("WatchComplication: no region available.")
            let fallback = NextDepartureComplication.fallbackBookmark(from: bookmarkStore.bookmarks)
            return WatchComplicationContent(bookmark: fallback, departures: [:], fetchedAt: nil)
        }

        guard let topBookmark = NextDepartureComplication.topBookmark(
            from: bookmarkStore.bookmarks,
            regionIdentifier: region.regionIdentifier
        ) else {
            Logger.info("WatchComplication: no bookmarks to load data for in current region.")
            return .empty
        }

        let selected = Array([topBookmark].prefix(max(1, maximumBookmarks)))
        guard let bookmark = selected.first else {
            return .empty
        }

        guard let apiKey = restServerAPIKey else {
            Logger.error("WatchComplication: no REST API key available.")
            return WatchComplicationContent(bookmark: bookmark, departures: [:], fetchedAt: nil)
        }

        let service = RESTAPIService.standalone(
            region: region,
            apiKey: apiKey,
            appVersion: appVersion,
            uuid: UserUUID.value(in: userDefaults),
            dataLoader: dataLoader
        )

        let departures = await BookmarkArrivalsLoader(minutesAfter: 90).departuresByWatchBookmark(
            for: selected,
            using: service
        )
        return WatchComplicationContent(
            bookmark: bookmark,
            departures: departures,
            fetchedAt: departures.isEmpty ? nil : Date()
        )
    }

    /// Builds a WidgetKit timeline using `WidgetTimelinePlanner` so departure transitions
    /// advance locally without consuming extra complication reload budget.
    public static func buildTimeline(from content: WatchComplicationContent, now: Date = Date()) -> Timeline<WatchComplicationEntry> {
        let bookmarks = content.bookmark.map { [$0] } ?? []
        let boardableDates = content.departures.values
            .flatMap { $0 }
            .filter { $0.departureEnabled && $0.hasPlausibleDepartureDate }
            .map(\.departureDate)
        let plan = WidgetTimelinePlanner.singleBookmarkComplication().plan(
            departureDates: boardableDates,
            now: now
        )

        let entries = plan.entryDates.map { entryDate in
            let visibleDepartures = content.departures.mapValues { departures in
                WidgetTimelinePlanner.boardableDepartures(departures, visibleAt: entryDate)
            }
            let state = NextDepartureComplication.resolve(
                watchBookmarks: bookmarks,
                departuresByBookmark: visibleDepartures,
                now: entryDate
            )
            return WatchComplicationEntry(date: entryDate, state: state, fetchedAt: content.fetchedAt)
        }

        return Timeline(entries: entries, policy: .after(plan.reloadDate))
    }
}

/// WatchKit/WidgetKit timeline provider for watchOS next-departure complications.
nonisolated public struct WatchComplicationTimelineProvider: TimelineProvider, Sendable {
    private let loaderProvider: @MainActor @Sendable () -> WatchComplicationDataLoader

    public init(loaderProvider: @escaping @MainActor @Sendable () -> WatchComplicationDataLoader = {
        WatchComplicationDataLoader.fromMainBundle()
    }) {
        self.loaderProvider = loaderProvider
    }

    public func placeholder(in context: Context) -> WatchComplicationEntry {
        WatchComplicationEntry(date: .now, state: .noBookmarks)
    }

    public func getSnapshot(in context: Context, completion: @escaping @Sendable (WatchComplicationEntry) -> Void) {
        if context.isPreview {
            completion(WatchComplicationEntry(date: .now, state: .noBookmarks))
            return
        }

        let maxBookmarks = WatchComplicationEntry.maximumBookmarks(for: context.family)
        let loaderProvider = self.loaderProvider
        Task { @MainActor in
            let loader = loaderProvider()
            let content = await loader.load(maximumBookmarks: maxBookmarks)
            let now = Date()
            let bookmarks = content.bookmark.map { [$0] } ?? []
            let state = NextDepartureComplication.resolve(
                watchBookmarks: bookmarks,
                departuresByBookmark: content.departures,
                now: now
            )
            completion(WatchComplicationEntry(date: now, state: state, fetchedAt: content.fetchedAt))
        }
    }

    public func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<WatchComplicationEntry>) -> Void) {
        let maxBookmarks = WatchComplicationEntry.maximumBookmarks(for: context.family)
        let loaderProvider = self.loaderProvider
        Task { @MainActor in
            let loader = loaderProvider()
            let content = await loader.load(maximumBookmarks: maxBookmarks)
            let timeline = WatchComplicationDataLoader.buildTimeline(from: content, now: Date())
            completion(timeline)
        }
    }
}
