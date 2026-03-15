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

    var body: some View {
        switch row.kind {
        case .loading:
            loadingRow
        case .noResults, .error:
            statusRow
        case .clearRecents:
            clearRecentsRow
        default:
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
                labelStack
                Spacer()
                if row.accessory == .disclosureIndicator {
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color(uiColor: ThemeColors.shared.brand))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Non-interactive status row — no results or error.
    private var statusRow: some View {
        HStack(spacing: 12) {
            leadingIcon
            labelStack
            Spacer()
        }
        .foregroundStyle(.secondary)
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
                if let icon = row.icon, case let .system(icon) = icon {
                    Image(systemName: icon)
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
            default:
                plainIcon(icon)
            }
        }
    }

    private var labelStack: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let attributed = row.attributedTitle {
                Text(AttributedString(attributed))
            } else if let title = row.title {
                Text(title)
                    .font(.body)
                    .fontWeight(row.kind.isPlacemark ? .semibold : .regular)
            }

            if let subtitle = row.subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
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

    /// Plain secondary icon — status rows, loading, etc.
    @ViewBuilder
    private func plainIcon(_ icon: SearchListRow.Icon) -> some View {
        iconImage(icon, size: 16)
            .frame(width: 32, height: 32)
            .foregroundStyle(.secondary)
    }

    /// Resolves Icon enum to a SwiftUI Image.
    @ViewBuilder
    private func iconImage(_ icon: SearchListRow.Icon, size: CGFloat, padding: CGFloat = 0) -> some View {
        switch icon {
        case .system(let name):
            Image(systemName: name)
                .font(.system(size: size - padding, weight: .medium))
        case .uiImage(let name):
            Image(uiImage: name)
                .resizable()
                .frame(width: size - padding, height: size - padding)
                .scaledToFit()
        }
    }
}
