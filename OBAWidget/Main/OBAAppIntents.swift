//
//  AppIntents.swift
//  OBAWidget
//
//  Created by Manu on 2024-10-12.
//

import Foundation


import WidgetKit
import AppIntents
import OBAKitCore


struct ConfigurationAppIntent: AppIntent, WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Two Bookmarks"
    static var description: IntentDescription = IntentDescription("Please select exactly two bookmarks for the widget to display.")
    
    
    
}

