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
        BookmarkEntry(date: .now, bookmarkDepartures: [])
    }
    
    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> BookmarkEntry {
        let data = await dataProvider.loadData()
        
        let entry = BookmarkEntry(date: .now, bookmarkDepartures: data)
     
        return entry
    }
    
    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<BookmarkEntry> {
        
        let data = await dataProvider.loadData()
  
        let entry = BookmarkEntry(date: .now, bookmarkDepartures: data)
        
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 3, to: Date())!
        
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
    
}
