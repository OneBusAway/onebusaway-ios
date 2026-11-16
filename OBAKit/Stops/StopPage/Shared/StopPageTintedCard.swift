//
//  StopPageTintedCard.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

/// The stop page's self-contained tinted card — a list section drawn as one
/// rounded, tint-washed box — shared by the service-alerts and on-demand
/// cards so the two stay visually identical. Rows go inside, separated by
/// `StopPageCardDivider`, usually led by a `StopPageCardHeader`.
struct StopPageTintedCard<Content: View>: View {
    /// `nil` for a neutral card: a plain fill and no border.
    let tint: Color?
    @ViewBuilder let content: Content

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    var body: some View {
        Section {
            VStack(spacing: 0) {
                content
            }
            .background(cardShape.fill(tint.map { $0.opacity(0.08) } ?? Color(uiColor: .secondarySystemFill)))
            .overlay(cardShape.strokeBorder(tint.map { $0.opacity(0.22) } ?? .clear, lineWidth: 1))
            .clipShape(cardShape)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }
}

/// A tinted card's header: a gradient badge and a title.
struct StopPageCardHeader: View {
    let systemImage: String
    let title: String
    let tint: Color

    /// The badge scales with Dynamic Type so its glyph never clips.
    @ScaledMetric(relativeTo: .subheadline) private var badgeSize: CGFloat = 30

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: badgeSize, height: badgeSize)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

/// A tappable card row: `label`, then a decorative chevron — the label is what
/// names the button.
struct StopPageCardRow<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                label
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The inset rule between a tinted card's rows.
struct StopPageCardDivider: View {
    var body: some View {
        Divider().padding(.leading, 14)
    }
}
