//
//  BookmarkControl.swift
//  OBAWidget
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import AppIntents
import SwiftUI
import WidgetKit
import OBAKitCore

/// A control for Control Center, the Lock Screen and the Action button that
/// opens one bookmarked stop.
///
/// The person picks the bookmark when adding the control. Tapping runs
/// `OpenBookmarkControlIntent`, which the app compiles too so it can run there.
/// Lookups go through `BookmarkControlCatalog` so the tests can reach them.
/// The app reloads the control whenever bookmarks change
/// (`BookmarkWidgetRefresher`), so a rename or delete shows up without waiting
/// for the system.
struct BookmarkControl: ControlWidget {
    static let kind = "OBABookmarkControl"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: Self.kind, provider: BookmarkControlValueProvider()) { value in
            ControlWidgetButton(action: OpenBookmarkControlIntent(bookmarkID: value.bookmarkID)) {
                Label(value.title, systemImage: "bookmark.fill")
            }
        }
        // From this extension's AppIntents.strings: the gallery and the Action
        // button settings read these out of process, like the intent titles.
        .displayName(LocalizedStringResource("bookmark_control.display_name", defaultValue: "Bookmark", table: "AppIntents", bundle: #bundle))
        .description(LocalizedStringResource("bookmark_control.description", defaultValue: "Open a bookmarked stop.", table: "AppIntents", bundle: #bundle))
        .promptsForUserConfiguration()
    }
}

/// What the control shows: the bookmark's current name, or the placeholder
/// when it has none.
struct BookmarkControlValue: Sendable {
    let bookmarkID: UUID?
    let title: String
}

struct BookmarkControlValueProvider: AppIntentControlValueProvider {
    func previewValue(configuration: SelectBookmarkControlIntent) -> BookmarkControlValue {
        BookmarkControlValue(bookmarkID: nil, title: configuration.bookmark?.name ?? WidgetStrings.controlChooseBookmark)
    }

    func currentValue(configuration: SelectBookmarkControlIntent) async throws -> BookmarkControlValue {
        // Looked up again rather than trusting the saved entity, so a renamed
        // bookmark shows its new name and a deleted one shows the placeholder.
        guard let id = configuration.bookmark?.id,
              let bookmark = BookmarkControlStore.bookmarks(ids: [id]).first else {
            return BookmarkControlValue(bookmarkID: nil, title: WidgetStrings.controlChooseBookmark)
        }
        return BookmarkControlValue(bookmarkID: bookmark.id, title: bookmark.name)
    }
}

// MARK: - Intents

/// The control's settings: which bookmark it opens.
struct SelectBookmarkControlIntent: ControlConfigurationIntent {
    static let title = LocalizedStringResource("select_bookmark_control_intent.title", defaultValue: "Choose Bookmark", table: "AppIntents", bundle: #bundle)
    static let isDiscoverable = false

    @Parameter(title: LocalizedStringResource("control_bookmark_entity.parameter_title", defaultValue: "Bookmark", table: "AppIntents", bundle: #bundle))
    var bookmark: ControlBookmarkEntity?

    init() {}
}

// MARK: - Entity

/// A bookmark as the control's picker lists it. Any bookmark in the current
/// region, stop or trip, since the control only opens its stop.
struct ControlBookmarkEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("control_bookmark_entity.type_name", defaultValue: "Bookmark", table: "AppIntents", bundle: #bundle)
    )
    static let defaultQuery = ControlBookmarkEntityQuery()

    let id: UUID
    let name: String
    let stopName: String

    init(_ bookmark: Bookmark) {
        id = bookmark.id
        name = bookmark.name
        stopName = bookmark.stop.name
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(stopName)")
    }
}

struct ControlBookmarkEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [ControlBookmarkEntity] {
        BookmarkControlStore.bookmarks(ids: identifiers).map(ControlBookmarkEntity.init)
    }

    func suggestedEntities() async throws -> [ControlBookmarkEntity] {
        BookmarkControlStore.bookmarks().map(ControlBookmarkEntity.init)
    }

    func entities(matching string: String) async throws -> [ControlBookmarkEntity] {
        BookmarkControlStore.bookmarks(matching: string).map(ControlBookmarkEntity.init)
    }
}
