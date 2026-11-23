//
//  StopStaleArrivalsNotice.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The card above the departures when a refresh failed after departures had
/// already loaded (`StopPageContent.showsStaleArrivalsNotice`).
///
/// Without it, the rows on screen are the last good fetch and keep counting
/// down as if they were live: the empty-state row that carries the error only
/// renders when the list is empty, and the map sheet has no "Updated: …" line
/// to go stale. Disappears as soon as a refresh succeeds, because a successful
/// fetch clears `StopViewModel.operationError`.
///
/// A plain-value view: it never touches `StopViewModel`.
struct StopStaleArrivalsNotice: View {
    /// The classified error copy (`StopViewModel.operationErrorMessage`).
    let errorText: String?
    /// The view model's freshness line ("Updated: 3 min ago"). `nil` where the
    /// presentation already shows freshness, so it isn't said twice.
    let statusText: String?
    /// A refresh is in flight; Retry would be a no-op until it lands.
    let isRetrying: Bool
    let onRetry: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    static let title = OBALoc(
        "stop_page.stale.title",
        value: "Couldn't update departures",
        comment: "Title of the card shown above a stop's departures when refreshing them failed, so the times on screen are from the last successful update."
    )

    var body: some View {
        StopPageTintedCard(tint: Color(uiColor: ThemeColors.shared.warningText)) {
            // Stacked at accessibility sizes, where the button beside the text
            // would squeeze the message into a one-word column.
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
            layout {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "exclamationmark.icloud")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(uiColor: ThemeColors.shared.warningText))
                        .accessibilityHidden(true) // decorative; the title carries the meaning
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if let errorText {
                            Text(errorText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if let statusText {
                            Text(statusText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // One stop for the message; Retry stays its own button after it.
                .accessibilityElement(children: .combine)

                Button(Strings.retry, action: onRetry)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isRetrying)
            }
            .padding(12)
        }
    }
}

#Preview("Stale arrivals") {
    List {
        StopStaleArrivalsNotice(
            errorText: "Couldn't reach the Puget Sound server. Check your connection and try again.",
            statusText: "Updated: 4 min ago",
            isRetrying: false,
            onRetry: {}
        )
    }
    .listStyle(.plain)
}
