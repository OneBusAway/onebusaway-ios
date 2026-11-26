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

    /// Offline only: each saved bookmark's timetable departures, for once its
    /// saved departures have left. See `SavedBookmarkDepartures`.
    let scheduledDepartures: [UUID: [ScheduledDeparture]]

    /// When the saved departures shown were saved; nil when all are live.
    let savedAt: Date?

    /// Zero-based index of the displayed bookmark page (`.systemMedium` only).
    let currentPage: Int

    /// Total number of bookmark pages available for the widget family.
    let totalPages: Int

    init(
        date: Date,
        bookmarks: [Bookmark],
        departures: [UUID: [ArrivalDeparture]] = [:],
        fetchedAt: Date? = nil,
        scheduledDepartures: [UUID: [ScheduledDeparture]] = [:],
        savedAt: Date? = nil,
        currentPage: Int = 0,
        totalPages: Int? = nil
    ) {
        self.date = date
        self.bookmarks = bookmarks
        self.departures = departures
        self.fetchedAt = fetchedAt
        self.scheduledDepartures = scheduledDepartures
        self.savedAt = savedAt
        self.currentPage = currentPage
        self.totalPages = totalPages ?? (bookmarks.isEmpty ? 0 : 1)
    }

    /// How many bookmarks a widget of `family` can show. The one source of
    /// truth for it: the view renders this many rows, and the provider fetches
    /// arrivals for exactly this many bookmarks, so a reload never pays for a
    /// stop nobody will see.
    static func maximumBookmarks(for family: WidgetFamily) -> Int {
        family == .systemLarge ? 7 : WidgetBookmarkPaginator.mediumPageSize
    }

    /// Returns a formatted string representing the last updated time.
    public func lastUpdatedAt(with formatters: Formatters) -> String {
        guard let fetchedAt, !bookmarks.isEmpty else { return "--" }
        return formatters.timeFormatter.string(from: fetchedAt)
    }

    /// The header: when the departures were fetched or, offline, when the
    /// saved ones were saved.
    func headerText(with formatters: Formatters) -> String {
        if let savedAt, !bookmarks.isEmpty {
            return WidgetStrings.offlineSaved(at: formatters.timeFormatter.string(from: savedAt))
        }
        return WidgetStrings.lastUpdated(at: lastUpdatedAt(with: formatters))
    }
}
