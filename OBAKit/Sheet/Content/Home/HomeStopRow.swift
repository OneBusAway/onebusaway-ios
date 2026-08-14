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
/// Uses headline heavy for stop name and footnote secondary for subtitle,
/// matching the bookmark card rows. Includes an untinted squircle transport icon
/// and a trailing chevron.
struct HomeStopRow: View {
    let stop: Stop
    let onSelect: () -> Void

    private let brandColor = Color(uiColor: ThemeColors.shared.brand)

    /// Name, direction, routes, and stop ID — the same label the map pins use.
    ///
    /// Not `stop.name` joined with `stop.subtitle`: `subtitle` comes from `Stop`'s
    /// `MKAnnotation` conformance and embeds a newline between the stop code and
    /// the route list, which VoiceOver reads verbatim.
    private var accessibilityLabelText: String {
        Formatters.formattedAccessibilityLabel(stop: stop)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Untinted squircle icon, matching StopRowItem exactly
                Image(uiImage: Icons.squircleTransportIcon(for: stop.prioritizedRouteTypeForDisplay))
                    .frame(width: Icons.squircleIconSize, height: Icons.squircleIconSize)

                // Title and subtitle stack
                VStack(alignment: .leading, spacing: 0) {
                    Text(stop.name)
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if let subtitle = stop.subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
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
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityAddTraits(.isButton)
    }
}
