//
//  AppIntents.swift
//  OBAWidget
//
//  Created by Manu on 2024-10-12.
//

import WidgetKit
import AppIntents
import OBAKitCore

struct ConfigurationAppIntent: AppIntent, WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Bookmarks"
    static var description: IntentDescription = IntentDescription("Get the transit info")

    func perform() async throws -> some IntentResult {
        return .result()
    }
}
