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

    var body: some View {
        HStack(spacing: 12) {
            refreshButton

            Text(title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
                .opacity(titleOpacity)
                // Hidden from VoiceOver while invisible; the header below names
                // the stop in that state.
                .accessibilityHidden(titleOpacity < 0.5)

            closeButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var refreshButton: some View {
        Button(action: onRefresh) {
            ZStack {
                if isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 30, height: 30)
            .background(Color(uiColor: .secondarySystemFill), in: Circle())
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isRefreshing)
        .accessibilityLabel(Strings.refresh)
        .accessibilityValue(statusText)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Color(uiColor: .secondarySystemFill), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.close)
    }
}

#Preview("Expanded") {
    StopDetailsSheetTopBar(title: "3rd Ave & Pike St", titleOpacity: 0, statusText: "Updated: Just Now", isRefreshing: false, onRefresh: {}, onClose: {})
}

#Preview("Collapsed") {
    StopDetailsSheetTopBar(title: "3rd Ave & Pike St", titleOpacity: 1, statusText: "Updated: Just Now", isRefreshing: true, onRefresh: {}, onClose: {})
}
