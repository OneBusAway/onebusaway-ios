//
//  WidgetKinds.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

#if os(iOS)

/// Extension kind identifiers shared by the app (`OBAKit`, which requests
/// reloads) and the widget extension (`OBAWidget`, which registers them).
/// Keeping a single source of truth here prevents the two targets from
/// silently drifting apart (#2006).
public enum WidgetKinds {
    /// Registered `kind` of the Home Screen bookmarks widget (`OBAWidget`).
    public static let bookmarksWidget = "OBAWidget"

    /// Every Home Screen widget timeline kind registered by the widget extension.
    public static let timelineKinds = [bookmarksWidget]

    /// Registered `kind` of the Control Center / Lock Screen / Action button
    /// Bookmark control (`BookmarkControl`).
    public static let bookmarkControl = "OBABookmarkControl"
}

#endif // os(iOS)
