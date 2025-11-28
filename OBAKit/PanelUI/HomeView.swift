//
//  HomeView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The main panel view for the home screen, combining nearby stops, recent stops, and bookmarks.
/// Modeled on the Apple Maps panel experience.
struct HomeView: View {
    let application: Application
    let nearbyStops: [Stop]
    let onStopSelected: (Stop) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Nearby Stops section
                NearbyStopsSection(
                    stops: nearbyStops,
                    iconFactory: application.stopIconFactory,
                    onStopSelected: onStopSelected
                )

                // Recent Stops section
                RecentStopsView(application: application, onStopSelected: onStopSelected)

                // Bookmarks section
                BookmarksView(application: application, onStopSelected: onStopSelected)
            }
        }
    }
}

/// A section displaying nearby stops on the map
struct NearbyStopsSection: View {
    let stops: [Stop]
    let iconFactory: StopIconFactory
    let onStopSelected: (Stop) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Text("Nearby Stops")
                    .font(.headline)
                Spacer()
                if !stops.isEmpty {
                    Text("\(stops.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Content
            if stops.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(stops.prefix(5)) { stop in
                        StopRowView(stop: stop, iconFactory: iconFactory) {
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
            Image(systemName: "mappin.slash")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No Stops in This Area")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Zoom in to see nearby stops")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
