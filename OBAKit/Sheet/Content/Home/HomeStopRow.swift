//
//  HomeStopRow.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// A stop row for the home sheet's nearby and recent sections.
///
/// Mirrors the UIKit `StopRowItem` appearance: untinted squircle transport icon,
/// stop name in title3 bold, subtitle in body, and a trailing chevron.
struct HomeStopRow: View {
    let stop: Stop
    let onSelect: () -> Void

    private let brandColor = Color(uiColor: ThemeColors.shared.brand)

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Untinted squircle icon, matching StopRowItem exactly
                Image(uiImage: Icons.squircleTransportIcon(for: stop.prioritizedRouteTypeForDisplay))
                    .frame(width: Icons.squircleIconSize, height: Icons.squircleIconSize)

                // Title and subtitle stack
                VStack(alignment: .leading, spacing: 0) {
                    Text(stop.name)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let subtitle = stop.subtitle {
                        Text(subtitle)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Trailing chevron
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(brandColor)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement()
        .accessibilityLabel(stop.name)
        .accessibilityHint(stop.subtitle ?? "")
        .accessibilityAddTraits(.isButton)
    }
}
