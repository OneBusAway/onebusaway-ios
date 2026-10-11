//
//  AppIntents.swift
//  OBAWidget
//
//  Created by Manu on 2024-10-12.
//

import WidgetKit
import AppIntents
import OBAKitCore

/// Strings resolve from this extension's `AppIntents.strings`; see `RefreshWidgetIntent`.
struct ConfigurationAppIntent: AppIntent, WidgetConfigurationIntent {
    static let title = LocalizedStringResource("widget_configuration_intent.title", defaultValue: "Bookmarks", table: "AppIntents", bundle: #bundle)
    static let description = IntentDescription(LocalizedStringResource("widget_configuration_intent.description", defaultValue: "See upcoming departures for your bookmarks.", table: "AppIntents", bundle: #bundle))

    func perform() async throws -> some IntentResult {
        return .result()
    }
}
