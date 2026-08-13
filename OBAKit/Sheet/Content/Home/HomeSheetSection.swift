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
    case nearby
    case recent
    case bookmarks

    /// How many items each section previews before the header's chevron takes
    /// over. Defined once so the three sections can't drift apart.
    static let itemLimit = 4
}
