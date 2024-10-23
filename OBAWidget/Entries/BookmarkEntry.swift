//
//  BookmarkEntry.swift
//  OBAWidget
//
//  Created by Manu on 2024-10-18.
//

import OBAKitCore
import WidgetKit


fileprivate let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a"
    return formatter
}()


/// A struct representing a timeline entry for bookmarks in a widget.
///
/// for displaying bookmarks in the widget context.
struct BookmarkEntry: TimelineEntry {
    
    let date: Date
    
    /// bookmarks associated with this `BookmarkEntry`.
    let bookmarks: [Bookmark]
    
    /// A formatted string representing the last updated time.
    var lastUpdatedAt: String {
        bookmarks.isEmpty ? "--" : dateFormatter.string(from: date)
    }
    
}

