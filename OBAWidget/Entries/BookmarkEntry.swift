//
//  BookmarkEntry.swift
//  OBAWidget
//
//  Created by Manu on 2024-10-18.
//

import OBAKitCore
import WidgetKit

/// A timeline entry for the bookmarks widget. Carries everything its view
/// renders: WidgetKit may draw an entry long after the provider that built it
/// has gone, so a view that reaches back into a shared provider for its
/// arrivals shows whatever that provider happens to hold by then.
struct BookmarkEntry: TimelineEntry {

    let date: Date

    /// bookmarks associated with this `BookmarkEntry`.
    let bookmarks: [Bookmark]

    /// Departures strictly after `date`, keyed by `Bookmark.id`. A bookmark that
    /// is **absent** has no data (its fetch failed, or there is no region); one
    /// mapped to `[]` was fetched and has nothing coming.
    let departures: [UUID: [ArrivalDeparture]]

    /// When `departures` was fetched; nil when nothing was.
    let fetchedAt: Date?

    init(date: Date, bookmarks: [Bookmark], departures: [UUID: [ArrivalDeparture]] = [:], fetchedAt: Date? = nil) {
        self.date = date
        self.bookmarks = bookmarks
        self.departures = departures
        self.fetchedAt = fetchedAt
    }

    /// How many bookmarks a widget of `family` can show. The one source of
    /// truth for it: the view renders this many rows, and the provider fetches
    /// arrivals for exactly this many bookmarks, so a reload never pays for a
    /// stop nobody will see.
    static func maximumBookmarks(for family: WidgetFamily) -> Int {
        switch family {
        case .systemLarge:
            return WidgetBookmarkFamily.systemLarge.maximumBookmarks
        case .systemMedium:
            return WidgetBookmarkFamily.systemMedium.maximumBookmarks
        case .accessoryCircular:
            return WidgetBookmarkFamily.accessoryCircular.maximumBookmarks
        case .accessoryRectangular:
            return WidgetBookmarkFamily.accessoryRectangular.maximumBookmarks
        case .accessoryInline:
            return WidgetBookmarkFamily.accessoryInline.maximumBookmarks
        case .systemSmall, .systemExtraLarge, .systemExtraLargePortrait:
            return WidgetBookmarkFamily.other.maximumBookmarks
        @unknown default:
            return WidgetBookmarkFamily.other.maximumBookmarks
        }
    }

    /// `true` when `family` is a single-bookmark Lock Screen or Watch complication family.
    static func isAccessoryFamily(_ family: WidgetFamily) -> Bool {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            return true
        case .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge, .systemExtraLargePortrait:
            return false
        @unknown default:
            return false
        }
    }

    /// Deep-link URL that opens the bookmark's stop in the host app.
    static func deepLinkURL(stopID: StopID, regionIdentifier: Int) -> URL {
        let router = URLSchemeRouter(scheme: Bundle.main.extensionURLScheme!)
        return router.encodeViewStop(stopID: stopID, regionID: regionIdentifier)
    }

    /// Returns a formatted string representing the last updated time.
    public func lastUpdatedAt(with formatters: Formatters) -> String {
        guard let fetchedAt, !bookmarks.isEmpty else { return "--" }
        return formatters.timeFormatter.string(from: fetchedAt)
    }
}
