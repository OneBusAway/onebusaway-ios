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
    var textStyle: UIFont.TextStyle = .body

    func makeUIView(context: Context) -> MarqueeLabel {
        let label = MarqueeLabel(frame: .zero)
        label.adjustsFontForContentSizeCategory = true
        label.trailingBuffer = ThemeMetrics.padding
        label.fadeLength = ThemeMetrics.padding
        label.textColor = .label
        // Leave the width to SwiftUI's proposal: the text's natural width would
        // otherwise push the row's other content aside.
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: MarqueeLabel, context: Context) {
        let font = UIFont.preferredFont(forTextStyle: textStyle)
        if label.font != font {
            label.font = font
        }
        if label.text != text {
            label.text = text
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView label: MarqueeLabel, context: Context) -> CGSize? {
        let natural = label.intrinsicContentSize
        guard let width = proposal.width, width.isFinite else { return natural }
        return CGSize(width: min(width, natural.width), height: natural.height)
    }
}
