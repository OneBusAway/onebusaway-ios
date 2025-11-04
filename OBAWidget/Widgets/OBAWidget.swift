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
    let dataProvider = WidgetDataProvider.shared

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
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
