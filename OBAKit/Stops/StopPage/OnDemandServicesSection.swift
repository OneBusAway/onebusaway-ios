//
//  OnDemandServicesSection.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore
import SwiftUI

/// The stop page's on-demand card: one row per service that covers this
/// stop, styled like `ServiceAlertsSection` (a self-contained tinted card with
/// a header row) but never collapsible — there are one or two rows at most.
struct OnDemandServicesSection: View {
    let services: [OnDemandService]
    let onSelect: (OnDemandService) -> Void

    /// What the rows render; exposed so tests assert the projection without a host.
    struct Row: Identifiable, Equatable {
        let id: String
        let title: String
        let subtitle: String
    }

    var rows: [Row] {
        services.map { Row(id: $0.id, title: $0.name, subtitle: Strings.onDemandKindTitle($0.serviceKind)) }
    }

    func select(_ row: Row) {
        guard let service = services.first(where: { $0.id == row.id }) else { return }
        onSelect(service)
    }

    @ScaledMetric(relativeTo: .subheadline) private var badgeSize: CGFloat = 30

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    var body: some View {
        Section {
            VStack(spacing: 0) {
                headerRow
                ForEach(rows) { row in
                    Divider().padding(.leading, 14)
                    serviceRow(row)
                }
            }
            .background(cardShape.fill(Color.accentColor.opacity(0.08)))
            .overlay(cardShape.strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 1))
            .clipShape(cardShape)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "car.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: badgeSize, height: badgeSize)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(Strings.onDemandSectionTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityAddTraits(.isHeader)
    }

    private func serviceRow(_ row: Row) -> some View {
        Button {
            select(row)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(row.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
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
