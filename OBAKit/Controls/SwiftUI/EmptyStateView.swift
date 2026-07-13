//
//  EmptyStateView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Reusable empty / loading / informational state for SwiftUI views.
///
/// Wraps `ContentUnavailableView` so call sites declare *what* to display
/// (title, SF Symbol, optional action) instead of re-spelling the underlying
/// initializer each time. Use `ErrorView` for richer error rendering with
/// classification; use this for plain status messages (loading, empty list,
/// "no results", info).
struct EmptyStateView<Actions: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } actions: {
            actions()
        }
    }
}

// MARK: - No-actions convenience

extension EmptyStateView where Actions == EmptyView {
    init(title: String, systemImage: String) {
        self.init(title: title, systemImage: systemImage, actions: { EmptyView() })
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Informational") {
    EmptyStateView(title: "No routes found nearby.", systemImage: "magnifyingglass")
}

#Preview("With Action") {
    EmptyStateView(title: "No active vehicle found on this route near you", systemImage: "bus") {
        Button("Try Again") { }
    }
}
#endif
