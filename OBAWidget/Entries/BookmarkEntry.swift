//
//  BookmarkEntry.swift
//  OBAWidget
//
//  Created by Manu on 2024-10-18.
//

import OBAKitCore
import WidgetKit

struct BookmarkEntry: TimelineEntry {
    let date: Date
    let bookmarks: [Bookmark]
//    let isRefreshing: Bool
}
