//
//  MarqueeText.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit
import OBAKitCore

/// A single line of text that scrolls when it is wider than the space it is given, and sits
/// still when it fits. With Reduce Motion on it truncates instead; see `MarqueeLabel`.
struct MarqueeText: UIViewRepresentable {
    let text: String
    let textStyle: UIFont.TextStyle

    func makeUIView(context: Context) -> MarqueeLabel {
        let label = MarqueeLabel(frame: .zero)
        label.trailingBuffer = ThemeMetrics.padding
        label.fadeLength = ThemeMetrics.padding
        return label
    }

    // The font follows SwiftUI's environment rather than `adjustsFontForContentSizeCategory`:
    // SwiftUI re-measures after an update, but not after the label rescales itself, which
    // would leave the row sized for the old font. MarqueeLabel's setters ignore unchanged
    // values, so an update doesn't restart the scroll.
    func updateUIView(_ label: MarqueeLabel, context: Context) {
        let environment = context.environment
        let traits = UITraitCollection { traits in
            traits.preferredContentSizeCategory = UIContentSizeCategory(environment.dynamicTypeSize)
            traits.legibilityWeight = environment.legibilityWeight == .bold ? .bold : .regular
        }
        label.font = UIFont.preferredFont(forTextStyle: textStyle, compatibleWith: traits)
        label.text = text
    }

    // Never wider than the proposal, so a long title scrolls instead of pushing the row apart.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView label: MarqueeLabel, context: Context) -> CGSize? {
        let natural = label.intrinsicContentSize
        guard let width = proposal.width, width.isFinite else { return natural }
        return CGSize(width: min(width, natural.width), height: natural.height)
    }
}
