//
//  TitleFonts.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

/// The fonts for a stop's name or a trip's headsign used as a title, so every
/// surface draws them alike. Public so the widget extension and Live
/// Activities can use them.
///
/// Semibold, and no heavier: a list of names in heavy or bold reads as a wall,
/// and leaves nothing for the numbers that matter more (countdowns, route
/// badges), which keep their heavier weights.
public extension Font {
    /// A stop's name or a headsign as the title of a row or a card.
    /// `.headline` is semibold body text.
    static var stopRowTitle: Font { .headline }

    /// A stop's name or a headsign heading a page or a trip's card.
    static var stopPageTitle: Font { .title2.weight(.semibold) }

    /// A headsign heading a smaller card, such as the trip page's.
    static var stopCardTitle: Font { .title3.weight(.semibold) }
}
