//
//  RecentStopsView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// A section view displaying the user's recently viewed stops
struct RecentStopsView: View {
    let application: Application
    let onStopSelected: (Stop) -> Void

    /// Recent stops filtered by the current region
    private var recentStops: [Stop] {
        guard let region = application.currentRegion else { return [] }
        return application.userDataStore.recentStops
            .filter { $0.regionIdentifier == region.regionIdentifier }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Text("Recent Stops")
                    .font(.headline)
                Spacer()
                if !recentStops.isEmpty {
                    Text("\(recentStops.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Content
            if recentStops.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(recentStops.prefix(5)) { stop in
                        StopRowView(stop: stop, iconFactory: application.stopIconFactory) {
                            onStopSelected(stop)
                        }
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No Recent Stops")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Stops you view will appear here")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
