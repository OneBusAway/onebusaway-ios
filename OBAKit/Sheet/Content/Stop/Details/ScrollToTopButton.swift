//
//  ScrollToTopButton.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The stop sheet's floating "back to the top" control.
///
/// Wears the same interactive Liquid Glass circle as `StopPageActionRow` and
/// `StopDetailsSheetTopBar`, so the sheet's chrome reads as one system rather
/// than three unrelated surfaces.
///
/// A plain-value view: it takes its visibility and its action from the caller and
/// owns no state.
struct ScrollToTopButton: View {

    let isVisible: Bool
    let action: () -> Void

    private static let buttonSize: CGFloat = 34

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.up")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .glassCircleLabel(diameter: Self.buttonSize)
        }
        .glassCircleSurface()
        .accessibilityLabel(OBALoc(
            "stop_page.scroll_to_top",
            value: "Scroll to top",
            comment: "VoiceOver label for the button that returns the stop page's departure list to the top."
        ))
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.8)
        // Fully out of the accessibility tree when hidden, so VoiceOver cannot
        // land on an invisible control.
        .accessibilityHidden(!isVisible)
        .allowsHitTesting(isVisible)
    }
}

#Preview("Visible") {
    ScrollToTopButton(isVisible: true, action: {})
}

#Preview("Hidden") {
    ScrollToTopButton(isVisible: false, action: {})
}
