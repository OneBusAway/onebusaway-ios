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
/// Uses `Font.stopRowTitle` for the stop name and footnote secondary for subtitle,
/// matching the bookmark card rows. Includes an untinted squircle transport icon
/// and a trailing chevron.
struct HomeStopRow: View {
    let stop: Stop
    let onSelect: () -> Void

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
                        .font(.stopRowTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(stop.subtitle(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                HomeRowChevron()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityAddTraits(.isButton)
    }
}

/// An alarm row for the home sheet's Alarms section: the trip the alarm is
/// set on, styled like `HomeStopRow`.
struct HomeAlarmRow: View {
    let title: String
    /// Whether the trip is loading, which replaces the chevron with a spinner.
    let isLoading: Bool
    let onSelect: () -> Void

    /// The darker brand green, as Explore's tiles use it on a pale fill.
    private let brand = Color(uiColor: ThemeColors.shared.brandAccent)

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: "alarm")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(brand)
                    .frame(width: Icons.squircleIconSize, height: Icons.squircleIconSize)
                    .background(brand.opacity(0.14), in: .rect(cornerRadius: Icons.squircleIconSize * Icons.squircleCornerRadiusRatio))
                    .accessibilityHidden(true)

                Text(title)
                    .font(.stopRowTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer()

                if isLoading {
                    ProgressView()
                } else {
                    HomeRowChevron()
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// The brand-green chevron at the end of the home sheet's rows.
struct HomeRowChevron: View {
    var body: some View {
        Image(systemName: "chevron.forward")
            .font(.footnote)
            .fontWeight(.semibold)
            .foregroundStyle(Color(uiColor: ThemeColors.shared.brand))
            .accessibilityHidden(true)
    }
}
