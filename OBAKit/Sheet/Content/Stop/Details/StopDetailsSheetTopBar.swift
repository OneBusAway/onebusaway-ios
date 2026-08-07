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

/// The stop sheet's pinned top strip: Refresh, the stop name, and Close.
///
/// It replaces the navigation bar the pushed presentation uses. The sheet has
/// no bar of its own, and this strip is the one piece of chrome that never
/// scrolls away — so Close remains reachable in every state, including a first
/// fetch that failed and left no header at all.
///
/// The title fades in as the map header collapses, so the sheet always names
/// the stop the rider is looking at without repeating it while the header is
/// on screen.
struct StopDetailsSheetTopBar: View {
    let title: String
    /// 0 while the header is expanded, 1 once it has collapsed.
    let titleOpacity: Double
    /// "Updated: Just Now" — the refresh button's VoiceOver value only. A
    /// visible label that rewrites itself every few seconds makes the bar feel
    /// restless, which is why `StopPageToolbar` hides it the same way.
    let statusText: String
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onClose: () -> Void

    /// Deliberately smaller than the action row's 34pt circles: this bar is
    /// chrome, not a row of primary actions. The two share everything else —
    /// glass surface, neutral palette and a 44pt hit region — so they still
    /// read as one system without either being hard to hit.
    private static let buttonSize: CGFloat = 32

    // MARK: - Body

    var body: some View {
        HStack(spacing: 12) {
            titleLabel
            controls
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Subviews

    private var titleLabel: some View {
        Text(title)
            .font(.headline)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(titleOpacity)
            // Hidden from VoiceOver while invisible; the header below names the
            // stop in that state.
            .accessibilityHidden(titleOpacity < 0.5)
    }

    /// Both controls sit together on the trailing edge.
    ///
    /// The spacing is the gap the 44pt hit regions need, not a visual choice:
    /// each 32pt circle claims 6pt beyond its own edge, so anything under 12
    /// would have Close quietly eating the right-hand side of Refresh.
    private var controls: some View {
        HStack(spacing: 12) {
            refreshButton
            closeButton
        }
    }

    private var refreshButton: some View {
        Button(action: onRefresh) {
            ZStack {
                if isRefreshing {
                    // `.regular` is `ControlSize`'s medium step — there is no
                    // `.medium` case. Matches the glyph it replaces more closely
                    // than `.small`, so the button does not appear to shrink
                    // while refreshing.
                    ProgressView().controlSize(.regular)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.body.weight(.semibold))
                }
            }
            .foregroundStyle(.primary)
            .glassCircleLabel(diameter: Self.buttonSize)
        }
        // The same interactive Liquid Glass surface the action row's circles
        // use, via the shared extension.
        .glassCircleSurface()
        .disabled(isRefreshing)
        .accessibilityLabel(Strings.refresh)
        .accessibilityValue(statusText)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .glassCircleLabel(diameter: Self.buttonSize)
        }
        .glassCircleSurface()
        .accessibilityLabel(Strings.close)
    }
}

#Preview("Expanded") {
    StopDetailsSheetTopBar(title: "3rd Ave & Pike St", titleOpacity: 0, statusText: "Updated: Just Now", isRefreshing: false, onRefresh: {}, onClose: {})
}

#Preview("Collapsed") {
    StopDetailsSheetTopBar(title: "3rd Ave & Pike St", titleOpacity: 1, statusText: "Updated: Just Now", isRefreshing: true, onRefresh: {}, onClose: {})
}
