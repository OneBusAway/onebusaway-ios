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

    /// Returns a formatted string representing the last updated time.
    public func lastUpdatedAt(with formatters: Formatters) -> String {
        guard let fetchedAt, !bookmarks.isEmpty else { return "--" }
        return formatters.timeFormatter.string(from: fetchedAt)
    }
}
