//
//  NextDepartureWidget.swift
//  OBAWidget
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore
import SwiftUI
import WidgetKit

/// Lock Screen complication widget showing the next upcoming departure for the
/// user's top favorited bookmark.
struct NextDepartureWidget: Widget {
    let kind: String = "NextDepartureWidget"

    var body: some WidgetConfiguration {
        let dataProvider = WidgetDataProvider.shared
        return AppIntentConfiguration(
            kind: kind,
            provider: BookmarkTimelineProvider(dataProvider: dataProvider)
        ) { entry in
            NextDepartureComplicationView(entry: entry, formatters: dataProvider.formatters)
                .containerBackground(.fill.quaternary, for: .widget)
        }
        .configurationDisplayName(WidgetStrings.nextDepartureGalleryDisplayName)
        .description(WidgetStrings.nextDepartureGalleryDescription)
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

#Preview(as: .accessoryCircular) {
    NextDepartureWidget()
} timeline: {
    BookmarkEntry(date: .now, bookmarks: [])
}

#Preview(as: .accessoryRectangular) {
    NextDepartureWidget()
} timeline: {
    BookmarkEntry(date: .now, bookmarks: [])
}

#Preview(as: .accessoryInline) {
    NextDepartureWidget()
} timeline: {
    BookmarkEntry(date: .now, bookmarks: [])
}
