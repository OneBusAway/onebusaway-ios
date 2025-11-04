//
//  BookmarkProvider.swift
//  OBAWidget
//
//  Created by Manu on 2024-10-14.
//

import Foundation
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

        await dataProvider.loadData()
        let data = dataProvider.getBookmarks()

        let entry = BookmarkEntry(date: .now, bookmarks: data)

        return entry
    }

    // MARK: Actual Timelines
    /// Generates timeline entries for the next 6 hours, starting from the current time.
    ///
    /// - **Current Time**: Let's say it's 12:00 PM.
    /// - **End Time**: 6 hours later, resulting in 6:00 PM.
    /// - **Entry Interval**: Creates entries every 30 minutes.
    /// - **Generated Entries**:
    ///   - 12:00 PM
    ///   - 12:30 PM
    ///   - 1:00 PM
    ///   - 1:30 PM
    ///   - so on ......
    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<BookmarkEntry> {
        await dataProvider.loadData()
        let data = dataProvider.getBookmarks()

        let currentDate = Date()
        let endDate = Calendar.current.date(byAdding: .hour, value: 6, to: currentDate)!

        // Generate entries for every 30 minutes within the defined time range.
        var entries: [BookmarkEntry] = []
        var date = currentDate
        while date < endDate {
            let entry = BookmarkEntry(date: date, bookmarks: data)
            entries.append(entry)
            date = Calendar.current.date(byAdding: .minute, value: 30, to: date)!
        }

        return Timeline(entries: entries, policy: .atEnd)
    }
}
