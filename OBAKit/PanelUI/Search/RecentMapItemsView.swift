//
//  RecentMapItemsView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import MapKit
import OBAKitCore

/// Shows recently searched map items from UserDataStore
struct RecentMapItemsView: View {
    let application: Application
    let onMapItemSelected: (MKMapItem) -> Void
    let onClearAll: () -> Void

    private var recentMapItems: [MKMapItem] {
        application.userDataStore.recentMapItems
    }

    var body: some View {
        if recentMapItems.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                // Section header
                HStack {
                    Text(Strings.recentSearches)
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                // Recent items list
                LazyVStack(spacing: 0) {
                    ForEach(recentMapItems, id: \.self) { mapItem in
                        MapItemRowView(
                            mapItem: mapItem,
                            currentLocation: application.locationService.currentLocation,
                            distanceFormatter: application.formatters.distanceFormatter,
                            brandColor: Color(ThemeColors.shared.brand),
                            onTap: { onMapItemSelected(mapItem) }
                        )
                        Divider().padding(.leading, 56)
                    }

                    // Clear button
                    clearButton
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No Recent Searches")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Places you search for will appear here")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var clearButton: some View {
        Button(action: onClearAll) {
            HStack(spacing: 12) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
                    .frame(width: 32)

                Text(Strings.clearRecentSearches)
                    .foregroundStyle(.red)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}
