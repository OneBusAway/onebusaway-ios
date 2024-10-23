//
//  BookmarkProvider.swift
//  OBAWidget
//
//  Created by Manu on 2024-10-14.
//

import Foundation
import WidgetKit

struct BookmarkTimelineProvider: AppIntentTimelineProvider {
    
    
    let dataProvider: WidgetDataProvider
    
    init(dataProvider: WidgetDataProvider) {
        self.dataProvider = dataProvider
    }
    
    // MARK: Placeholder
    func placeholder(in context: Context) -> BookmarkEntry {
        BookmarkEntry(date: .now, bookmarks: [])
    }
    
    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> BookmarkEntry {
        
        await dataProvider.loadData()
        let data = dataProvider.getBookmarks()
        
        let entry = BookmarkEntry(date: .now, bookmarks: data)

        return entry
    }
    
    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<BookmarkEntry> {
        
        await dataProvider.loadData()
        let data = dataProvider.getBookmarks()
        
        let entry = BookmarkEntry(date: .now, bookmarks: data)
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 3, to: Date())!
        
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
}
