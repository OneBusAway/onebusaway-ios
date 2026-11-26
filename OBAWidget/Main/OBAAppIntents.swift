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
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Pagination Intents

/// Advances `.systemMedium` widget bookmarks to the next page (wrapping to the first page).
struct NextBookmarkPageIntent: AppIntent {
    static let title = LocalizedStringResource(
        "next_bookmark_page_intent.title",
        defaultValue: "Next Bookmarks Page",
        table: "AppIntents",
        bundle: #bundle
    )
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await performBookmarkPageStep(delta: 1)
        return .result()
    }
}

/// Moves `.systemMedium` widget bookmarks to the previous page (wrapping to the last page).
struct PreviousBookmarkPageIntent: AppIntent {
    static let title = LocalizedStringResource(
        "previous_bookmark_page_intent.title",
        defaultValue: "Previous Bookmarks Page",
        table: "AppIntents",
        bundle: #bundle
    )
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await performBookmarkPageStep(delta: -1)
        return .result()
    }
}

@MainActor
private func performBookmarkPageStep(delta: Int) {
    let dataProvider = WidgetDataProvider.shared
    let bookmarkCount = dataProvider.currentRegionBookmarkCount()
    let paginator = WidgetBookmarkPaginator(userDefaults: dataProvider.userDefaults)
    // Returning from a `Button(intent:)`'s `perform()` already causes WidgetKit
    // to reload this widget's timeline, without forcing unrelated large widgets to refetch.
    paginator.step(by: delta, bookmarkCount: bookmarkCount)
}
