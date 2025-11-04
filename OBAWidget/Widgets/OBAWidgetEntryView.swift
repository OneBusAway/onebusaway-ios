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

    let dataProvider: WidgetDataProvider

    @Environment(\.widgetFamily) var widgetFamily

    private var maxBookmarkCount: Int {
        widgetFamily == .systemLarge ? 7 : 2
    }

    var body: some View {
        VStack(alignment: .leading) {
            // MARK: Header View
            HStack {
                Text(
                    "Last updated at: \(entry.lastUpdatedAt(with: dataProvider.formatters))"
                )
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)

                Spacer()
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
                                formatters: dataProvider.formatters,
                                departures: loadArrivalDeparture(with: bookmark)
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
        TripBookmarkKey(bookmark: bookmark).flatMap {
            dataProvider.lookupArrivalDeparture(with: $0)
        }
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
