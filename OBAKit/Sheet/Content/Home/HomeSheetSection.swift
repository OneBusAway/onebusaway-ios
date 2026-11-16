//
//  HomeSheetSection.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// The home sheet's content sections, in the order they render.
///
/// Order is fixed: an empty earlier section is omitted, never replaced by a
/// later one. Declared as its own type — rather than inline in the view model —
/// so each section model can reference `itemLimit` without depending on the
/// view model that composes them.
enum HomeSheetSection: Hashable {
    /// Recent high-severity agency alerts. First, as the UIKit map's nearby
    /// list has them, and with no index of its own.
    case alerts
    /// First of the rider's own: the section they chose, and the one that
    /// answers "when is my bus" without a tap.
    case bookmarks
    case nearby
    case recent
    /// Shortcuts to what the lists don't hold; see `HomeExploreItem`.
    case explore

    /// How many items each section previews before the header's chevron takes
    /// over. Defined once so the sections can't drift apart.
    static let itemLimit = 4

    /// Recent stops on Home, which has more sections above them than the
    /// sheet had before. The Recent tab has the rest.
    static let recentPreviewLimit = 3
}
