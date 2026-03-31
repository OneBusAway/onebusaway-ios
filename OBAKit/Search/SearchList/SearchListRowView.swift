//
//  SearchListRowView.swift
//  OBAKit
//
//  Created by Mohamed Sliem on 08/03/2026.
//

import SwiftUI
import OBAKitCore

struct SearchListRowView: View {
    let row: SearchListRow

    private let brandColor = Color(uiColor: ThemeColors.shared.brand)

    var body: some View {
        switch row.kind {
        case .loading:
            loadingRow
        case .noResults:
            statusRow
        case .error:
            errorRow
        case .clearRecents:
            clearRecentsRow
        case .quickSearch, .recentStop, .bookmark, .placemark:
            actionRow
        }
    }

    // MARK: - Row Variants

    /// Standard tappable row — stops, bookmarks, placemarks, quick search.
    private var actionRow: some View {
        Button {
            row.action?()
        } label: {
            HStack(spacing: 12) {
                leadingIcon
                labelStack()
                Spacer()
                if row.accessory == .disclosureIndicator {
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundStyle(brandColor)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Non-interactive status row — no results.
    private var statusRow: some View {
        HStack(spacing: 12) {
            leadingIcon
            labelStack(titleColor: .secondary)
            Spacer()
        }
    }

    /// Tappable error row — tapping retries the failed search.
    private var errorRow: some View {
        Button {
            row.action?()
        } label: {
            HStack(spacing: 16) {
                leadingIcon
                labelStack(
                    spacing: 4,
                    titleFont: .subheadline,
                    subtitleFont: .footnote.bold(),
                    subtitleColor: brandColor
                )

                Spacer()

                if row.action != nil {
                    retryBadge
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(row.action == nil)
    }

    private var retryBadge: some View {
        Image(systemName: "arrow.clockwise")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(brandColor)
            .padding(8)
            .background(brandColor.opacity(0.1))
            .clipShape(.circle)
            .accessibilityHidden(true)
    }

    /// Animated loading indicator row.
    private var loadingRow: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            if let title = row.title {
                Text(title)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Destructive clear recents row.
    private var clearRecentsRow: some View {
        Button(role: .destructive) {
            row.action?()
        } label: {
            HStack(spacing: 12) {
                if let icon = row.icon, case let .system(name) = icon {
                    Image(systemName: name)
                }
                if let title = row.title {
                    Text(title)
                }
            }
            .contentShape(.rect)
        }
    }

    // MARK: - Shared Subviews

    @ViewBuilder
    private var leadingIcon: some View {
        if let icon = row.icon {
            switch row.kind {
            case .placemark:
                badgedIcon(icon, size: 32, imagePadding: 14)
            case .quickSearch, .recentStop, .bookmark:
                badgedIcon(icon, size: 24, imagePadding: 8)
            case .error:
                plainIcon(icon, size: 20, tint: .orange)
            case .clearRecents, .loading, .noResults:
                plainIcon(icon)
            }
        }
    }

    @ViewBuilder
    private func labelStack(
        spacing: CGFloat = 2,
        titleFont: Font = .body,
        titleColor: Color = .primary,
        subtitleFont: Font = .callout,
        subtitleColor: Color = .secondary
    ) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            if let attributed = row.attributedTitle {
                Text(AttributedString(attributed))
                    .foregroundStyle(titleColor)
            } else if let title = row.title {
                Text(title)
                    .font(titleFont)
                    .fontWeight(row.kind.isPlacemark ? .semibold : .regular)
                    .foregroundStyle(titleColor)
            }

            if let subtitle = row.subtitle {
                Text(subtitle)
                    .font(subtitleFont)
                    .foregroundStyle(subtitleColor)
            }
        }
    }

    @ViewBuilder
    private func badgedIcon(_ icon: SearchListRow.Icon, size: CGFloat, imagePadding: CGFloat = 0) -> some View {
        iconImage(icon, size: size, padding: imagePadding)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
    }

    /// Plain icon — status rows, loading, and error.
    @ViewBuilder
    private func plainIcon(_ icon: SearchListRow.Icon, size: CGFloat = 16, tint: Color = .secondary) -> some View {
        let frameSize = max(size, 32)
        iconImage(icon, size: size)
            .frame(width: frameSize, height: frameSize)
            .foregroundStyle(tint)
    }

    /// Resolves Icon enum to a SwiftUI Image.
    @ViewBuilder
    private func iconImage(_ icon: SearchListRow.Icon, size: CGFloat, padding: CGFloat = 0) -> some View {
        switch icon {
        case .system(let name):
            Image(systemName: name)
                .font(.system(size: size - padding, weight: .medium))
        case .uiImage(let image):
            Image(uiImage: image)
                .resizable()
                .frame(width: size - padding, height: size - padding)
                .scaledToFit()
        }
    }
}
