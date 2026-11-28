//
//  OpenBookmarkControlIntent.swift
//  OBAWidget
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import AppIntents
import Foundation
import OBAKitCore

/// Runs when the Bookmark control (`BookmarkControl`) is tapped: opens the app
/// on the bookmark's stop.
///
/// This file is compiled into both the widget extension and the app
/// (`Apps/Shared/app_shared.yml`). A control can only bring its app forward
/// with an intent both define: with `openAppWhenRun`, the system launches the
/// app and performs the intent there. (`OpenURLIntent` from the extension does
/// not open the app's custom URL scheme.)
///
/// In the app it can't reach `Application`, so `perform` hands the stop over
/// with `BookmarkControlOpenRequest`, like Open Stop does. Strings come from
/// the `AppIntents` table of whichever bundle compiles it, so the app's and
/// the widget's tables both carry them.
struct OpenBookmarkControlIntent: AppIntent {
    static let title = LocalizedStringResource("open_bookmark_control_intent.title", defaultValue: "Open Bookmark", table: "AppIntents", bundle: #bundle)
    static let openAppWhenRun = true
    static let isDiscoverable = false

    /// A string rather than an entity, so a deleted bookmark still opens the app.
    @Parameter(title: LocalizedStringResource("open_bookmark_control_intent.parameter_title", defaultValue: "Bookmark", table: "AppIntents", bundle: #bundle))
    var bookmarkID: String?

    init() {}

    init(bookmarkID: UUID?) {
        self.bookmarkID = bookmarkID?.uuidString
    }

    func perform() async throws -> some IntentResult {
        // No bookmark (never set, or deleted since): opening the app is all there is to do.
        if let id = bookmarkID.flatMap(UUID.init(uuidString:)),
           let bookmark = BookmarkControlStore.bookmarks(ids: [id]).first {
            BookmarkControlOpenRequest.post(bookmark)
        }
        return .result()
    }
}
