//
//  PaginationFooterRow.swift
//  OBAKit
//
//  Created by Mohamed Sliem on 07/05/2026.
//

import SwiftUI

/// A sentinel row appended to the end of a list or section to drive infinite scroll.
/// Shows a spinner while loading and fires `onLoadMore` when it first becomes visible.
struct PaginationFooterRow: View {
    let isLoading: Bool
    let onLoadMore: () -> Void

    @State private var hasFired = false

    var body: some View {
        ProgressView()
            .scaleEffect(0.8)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
            .listRowSeparator(.hidden)
            .accessibilityLabel(
                OBALoc(
                    "list_view.pagination_footer.loading_more",
                    value: "Loading more items",
                    comment: "Accessibility label for the pagination loading footer shown at the bottom of a list when more items are being fetched."
                )
            )
            .onAppear {
                guard !isLoading, !hasFired else { return }
                hasFired = true
                onLoadMore()
            }
            .onChange(of: isLoading) { _, isNowLoading in
                if !isNowLoading {
                    hasFired = false
                }
            }
    }
}
