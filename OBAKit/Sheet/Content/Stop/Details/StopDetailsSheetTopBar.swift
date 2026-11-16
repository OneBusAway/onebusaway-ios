//
//  StopDetailsSheetTopBar.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The stop sheet's pinned top strip: the stop name, the sheet's actions
/// (`StopPageActionRow`) and Close.
///
/// It replaces the navigation bar the pushed presentation uses. The sheet has
/// no bar of its own, and this strip is the one piece of chrome that never
/// scrolls away — so its actions and Close remain reachable in every state,
/// including a first fetch that failed and left no header at all. It is the
/// sheet's only chrome: the departures run from under it to the sheet's
/// bottom edge.
///
/// The title fades in as the header scrolls away, so the sheet always names
/// the stop the rider is looking at without repeating it while the header is
/// on screen.
struct StopDetailsSheetTopBar<Actions: View>: View {
    let title: String
    /// 0 while the header is expanded, 1 once it has collapsed.
    let titleOpacity: Double
    /// Shows a spinner after the title while a refresh the rider asked for
    /// runs; Refresh itself is in the actions' More menu.
    let isRefreshing: Bool
    let onClose: () -> Void
    @ViewBuilder let actions: Actions

    /// Set by `stopSheetChrome` (via `sheetGlassBackground`) on iOS 26 in light
    /// mode, where this bar is a `safeAreaBar` over the sheet's glass.
    @Environment(\.drawsOnSheetGlass) private var onSheetGlass

    // MARK: - Body

    var body: some View {
        HStack(spacing: 12) {
            titleLabel
            controls
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(background)
        .overlay(alignment: .bottom) { Divider() }
    }

    /// None on sheet glass (iOS 26, light mode), where the bar is a `safeAreaBar` and the
    /// system's scroll edge effect keeps rows legible beneath it. Before that
    /// the rows scroll under an opaque strip.
    private var background: Color {
        onSheetGlass ? .clear : Color(uiColor: .systemBackground)
    }

    // MARK: - Subviews

    /// The title, and the refresh spinner after it: in the flexible space, so
    /// the controls don't shift as a refresh starts and ends.
    private var titleLabel: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                .opacity(titleOpacity)
                // Hidden from VoiceOver while invisible; the header below names
                // the stop in that state.
                .accessibilityHidden(titleOpacity < 0.5)
            if isRefreshing {
                ProgressView()
                    .accessibilityLabel(Strings.refresh)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// All on the trailing edge, Close last.
    ///
    /// The spacing is the gap the 44pt hit regions need, not a visual choice:
    /// each 32pt circle claims 6pt beyond its own edge, so anything under 12
    /// would have one quietly eating the side of the next.
    private var controls: some View {
        HStack(spacing: 12) {
            actions
            closeButton
        }
        // The circles are a fixed 32pt; a `.body` glyph past this size would
        // spill out of them. The actions carry the large content viewer for
        // the sizes beyond.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
                .glassCircleLabel(diameter: GlassCircleMetrics.chromeCircleSize)
        }
        .filledCircleSurface()
        .accessibilityLabel(Strings.close)
    }
}

#Preview("Expanded") {
    StopDetailsSheetTopBar(title: "3rd Ave & Pike St", titleOpacity: 0, isRefreshing: false, onClose: {}, actions: {
        Image(systemName: "bookmark")
    })
}

#Preview("Collapsed") {
    StopDetailsSheetTopBar(title: "3rd Ave & Pike St", titleOpacity: 1, isRefreshing: true, onClose: {}, actions: {
        Image(systemName: "bookmark")
    })
}
