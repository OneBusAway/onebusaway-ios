//
//  OBAWidget.swift
//  OBAWidget
//
//  Created by Manu on 2024-10-15.
//

import Foundation
import WidgetKit
import SwiftUI

struct OBAWidget: Widget {
    let kind: String = "OBAWidget"

    var body: some WidgetConfiguration {
        // WidgetDataProvider.shared is main-actor-isolated; Widget.body is
        // evaluated on the main actor, so resolve it here instead of in a
        // stored property (whose default value would be nonisolated).
        let dataProvider = WidgetDataProvider.shared
        return AppIntentConfiguration(
            kind: kind,
            provider: BookmarkTimelineProvider(dataProvider: dataProvider)
        ) { entry in
            OBAWidgetEntryView(entry: entry, dataProvider: dataProvider)
                .containerBackground(.fill.quaternary, for: .widget)
        }
        .supportedFamilies([.systemMedium, .systemLarge])

    }
}

#Preview(as: .systemMedium) {
    OBAWidget()
} timeline: {
    BookmarkEntry(date: .now, bookmarks: [])
    BookmarkEntry(date: .distantFuture, bookmarks: [])
}
