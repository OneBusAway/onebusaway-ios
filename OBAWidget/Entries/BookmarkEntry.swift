//
//  BookmarkEntry.swift
//  OBAWidget
//
//  Created by Manu on 2024-10-18.
//

import OBAKitCore
import WidgetKit

/// A struct representing a timeline entry for bookmarks in a widget.
///
/// for displaying bookmarks in the widget context.
struct BookmarkEntry: TimelineEntry {
    
    let date: Date
    
    /// bookmarks associated with this `BookmarkEntry`.
    let bookmarks: [Bookmark]
    
    /// Returns a formatted string representing the last updated time.
    public func lastUpdatedAt(with formatters: Formatters) -> String {
        bookmarks.isEmpty ? "--" : formatters.timeFormatter.string(from: date)
    }
    
}

