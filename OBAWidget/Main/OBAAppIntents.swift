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

// MARK: - RefreshWidgetIntent

/// This intent serves as a way to refresh the widget and its timelines.
///
/// The title is read out of process from this extension's metadata, so it
/// resolves from the extension's own `AppIntents.strings` (OBAWidget/Strings),
/// not OBAKitCore's tables. `#bundle` is the only form the metadata processor
/// accepts; see `TrackBookmarkIntent`.
struct RefreshWidgetIntent: AppIntent {
    static let title = LocalizedStringResource("refresh_widget_intent.title", defaultValue: "Refresh Widget", table: "AppIntents", bundle: #bundle)
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        do {
            _ = await WidgetTimelineReloader.shared.reload()
        } catch {
            // Guarantee perform never traps even on unexpected exceptions.
        }
        return .result()
    }
}
