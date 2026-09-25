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
/// stop, in the same `StopPageTintedCard` as `ServiceAlertsSection` but never
/// collapsible — there are one or two rows at most.
struct OnDemandServicesSection: View {
    let services: [OnDemandService]
    let onSelect: (OnDemandService) -> Void

    /// What the rows render; exposed so tests assert the projection without a host.
    var rows: [OnDemandServiceListing] {
        services.map(OnDemandServiceListing.init)
    }

    func select(_ row: OnDemandServiceListing) {
        guard let service = services.first(where: { $0.id == row.id }) else { return }
        onSelect(service)
    }

    var body: some View {
        StopPageTintedCard(tint: .accentColor) {
            StopPageCardHeader(systemImage: "car.fill", title: Strings.onDemandSectionTitle, tint: .accentColor)
                .accessibilityAddTraits(.isHeader)
            ForEach(rows) { row in
                StopPageCardDivider()
                serviceRow(row)
            }
        }
    }

    private func serviceRow(_ row: OnDemandServiceListing) -> some View {
        StopPageCardRow {
            select(row)
        } label: {
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
        }
    }
}
