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
                Text("Last updated at: \(formattedDate(entry.date))")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)
                
                Spacer()
                RefreshButton().invalidatableContent()
            }
            .padding(.bottom, 10)
            
            // MARK: Bookmark Row View
            if !entry.bookmarks.isEmpty {
                VStack(spacing: 10) {
                    ForEach(entry.bookmarks.prefix(maxBookmarkCount), id: \.self) { bookmark in
                        WidgetRowView(
                            bookmark: bookmark,
                            formatters: dataProvider.formatters,
                            departures: loadArrivalDeparture(with: bookmark)
                        )
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
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
    
    private func formattedDate(_ date: Date) -> String {
        entry.bookmarks.isEmpty ? "--" : Self.dateFormatter.string(from: date)
    }
    
    private func loadArrivalDeparture(with bookmark: Bookmark) -> [ArrivalDeparture]? {
        TripBookmarkKey(bookmark: bookmark).flatMap {
            dataProvider.lookupArrivalDeparture(with: $0)
        }
    }
    
    // MARK: Empty state view
    private var emptyStateView: some View {
        VStack {
            Spacer()
            Text(
                OBALoc(
                    "today_screen.no_data_description",
                    value: "Add bookmarks to Today View Bookmarks to see them here.",
                    comment: ""
                )
            )
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
