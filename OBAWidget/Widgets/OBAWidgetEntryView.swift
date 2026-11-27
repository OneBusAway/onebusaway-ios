//
//  OBAWidgetEntryView.swift
//  OBAWidgetEntryView
//
//  Created by Manu on 2024-10-12.
//

import OBAKitCore
import SwiftUI
import WidgetKit

struct OBAWidgetEntryView: View {

    var entry: BookmarkTimelineProvider.Entry

    let formatters: Formatters

    @Environment(\.widgetFamily) var widgetFamily

    private var maxBookmarkCount: Int {
        BookmarkEntry.maximumBookmarks(for: widgetFamily)
    }

    var body: some View {
        VStack(alignment: .leading) {
            // MARK: Header View
            HStack(spacing: 6) {
                // `Text(verbatim:)`: the string is already localized, and an
                // interpolated literal would be looked up as its own key.
                Text(verbatim: entry.headerText(with: formatters))
                    // A text style rather than a fixed 13pt, so it follows Dynamic Type.
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 4)

                if widgetFamily == .systemMedium, entry.totalPages > 1 {
                    WidgetPaginationControls(
                        currentPage: entry.currentPage,
                        totalPages: entry.totalPages
                    )
                }

                RefreshButton().invalidatableContent()
            }
            .padding(.bottom, 5)

            // MARK: Bookmark Row View
            if !entry.bookmarks.isEmpty {
                VStack(spacing: 10) {
                    ForEach(entry.bookmarks.prefix(maxBookmarkCount), id: \.self) { bookmark in
                        Link(destination: constructDeepLink(for: bookmark)) {
                            WidgetRowView(
                                bookmark: bookmark,
                                formatters: formatters,
                                departures: loadArrivalDeparture(with: bookmark),
                                scheduledDepartures: loadScheduledDepartures(with: bookmark),
                                entryDate: entry.date
                            )
                        }
                    }
                }
            } else {
                emptyStateView
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
    }

    // MARK: Helper functions
    private func loadArrivalDeparture(with bookmark: Bookmark) -> [ArrivalDeparture]? {
        entry.departures[bookmark.id]
    }

    /// Offline only, `nil` while live: the saved timetable's departures after
    /// this entry's date, strictly, as `WidgetTimelinePlanner` keeps live ones.
    private func loadScheduledDepartures(with bookmark: Bookmark) -> [ScheduledDeparture]? {
        entry.scheduledDepartures[bookmark.id]?.filter { $0.date > entry.date }
    }

    private func constructDeepLink(for bookmark: Bookmark) -> URL {
        let router = URLSchemeRouter(scheme: Bundle.main.extensionURLScheme!)
        return router.encodeViewStop(stopID: bookmark.stopID, regionID: bookmark.regionIdentifier)
    }

    // MARK: Empty state view
    private var emptyStateView: some View {
        VStack {
            Spacer()
            Text(LocalizationKeys.emptyStateString)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview(as: .systemMedium) {
    OBAWidget()
} timeline: {
    BookmarkEntry(date: .now, bookmarks: [])
    BookmarkEntry(date: .distantFuture, bookmarks: [])
}
