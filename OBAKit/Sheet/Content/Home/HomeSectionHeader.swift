//
//  HomeSectionHeader.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// A home sheet section header: title on the left, chevron on the right, the
/// whole row acting as one button into that section's full index.
///
/// One button rather than a label plus a separate chevron button, so the tap
/// target matches what the row looks like and VoiceOver reads one element.
struct HomeSectionHeader: View {
    let title: String
    let onSeeAll: () -> Void

    private let brandColor = Color(uiColor: ThemeColors.shared.brand)

    var body: some View {
        Button(action: onSeeAll) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(brandColor)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(OBALoc(
            "home_sheet.section_header.a11y_hint",
            value: "Shows all items in this section.",
            comment: "VoiceOver hint for a home sheet section header, which opens that section's full list."
        ))
    }
}

#if DEBUG
#Preview {
    HomeSectionHeader(title: "Nearby Stops") { }
        .padding()
}
#endif
