//
//  LiveActivityStaleChrome.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

/// User-visible treatment when ActivityKit marks a Live Activity stale.
///
/// Promote/demote and push paths carefully preserve `staleDate` (#1215), but
/// until the widget reads `context.isStale` a frozen countdown looks identical
/// to a live one (#1376). Keep the copy and dimming here so lock-screen and
/// Dynamic Island stay in sync without duplicating literals.
public enum LiveActivityStaleChrome {
    /// Same tone as the rental-map freshness footer: orange warning, plain language.
    public static var warningText: String {
        OBALoc(
            "live_activity.stale_warning",
            value: "This data may be out of date.",
            comment: "Shown on a Live Activity when ActivityKit marks it stale (no recent update)."
        )
    }

    /// The warning's color on the lock-screen card. Plain `.orange` was 2.2:1
    /// on the light card; `warningText` holds AA in both appearances. The
    /// Dynamic Island is always dark, where `.orange` is already fine.
    public static var warningColor: Color {
        Color(uiColor: ThemeColors.shared.warningText)
    }

    /// Dim the minutes/route chrome so a stale card cannot be mistaken for live.
    public static func contentOpacity(isStale: Bool) -> Double {
        isStale ? 0.55 : 1.0
    }
}
