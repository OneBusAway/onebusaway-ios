//
//  BookmarkProvider.swift
//  OBAWidget
//
//  Created by Manu on 2024-10-14.
//

import Foundation
import OBAKitCore
import WidgetKit

/// Timeline provider for generating widget updates based on bookmark data.
struct BookmarkTimelineProvider: AppIntentTimelineProvider {

    let dataProvider: WidgetDataProvider

    // MARK: Placeholder
    func placeholder(in context: Context) -> BookmarkEntry {
        BookmarkEntry(date: .now, bookmarks: [])
    }

    // MARK: Snapshot
    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> BookmarkEntry {
        let content = await dataProvider.load()
        return BookmarkEntry(date: .now, bookmarks: content.bookmarks, departures: content.departures, fetchedAt: content.fetchedAt)
    }

    // MARK: Actual Timelines
    /// One fetch, several entries, one slow reload.
    ///
    /// `WidgetTimelinePlanner` puts an entry at each departure boundary, so the
    /// widget drops a bus as it leaves without asking for a reload, and sets the
    /// reload 30 minutes out (60 when nothing is coming). Never reload on the
    /// next departure: WidgetKit budgets 40–70 reloads a day.
    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<BookmarkEntry> {
        let content = await dataProvider.load()
        let now = Date()

        let plan = WidgetTimelinePlanner().plan(
            departureDates: content.departures.values.flatMap { $0.map(\.arrivalDepartureDate) },
            now: now
        )

        let entries = plan.entryDates.map { date in
            BookmarkEntry(
                date: date,
                bookmarks: content.bookmarks,
                // `mapValues` keeps a fetched-but-now-empty bookmark present
                // (as `[]`), so it reads "no departures", not "no data".
                departures: content.departures.mapValues { $0.filter { $0.arrivalDepartureDate >= date } },
                fetchedAt: content.fetchedAt
            )
        }

        return Timeline(entries: entries, policy: .after(plan.reloadDate))
    }
}
