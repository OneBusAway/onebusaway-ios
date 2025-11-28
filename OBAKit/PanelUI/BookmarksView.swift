//
//  BookmarksView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// A section view displaying the user's bookmarked stops
struct BookmarksView: View {
    let application: Application
    let onStopSelected: (Stop) -> Void

    /// Bookmarks filtered by the current region
    private var bookmarks: [Bookmark] {
        guard let region = application.currentRegion else { return [] }
        return application.userDataStore.findBookmarks(in: region)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Text("Bookmarks")
                    .font(.headline)
                Spacer()
                if !bookmarks.isEmpty {
                    Text("\(bookmarks.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Content
            if bookmarks.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(bookmarks.prefix(5)) { bookmark in
                        BookmarkRowView(bookmark: bookmark) {
                            onStopSelected(bookmark.stop)
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
            Image(systemName: "bookmark")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No Bookmarks")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Save your favorite stops for quick access")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

/// A row displaying a single bookmark with transport icon, name, and optional trip info
struct BookmarkRowView: View {
    let bookmark: Bookmark
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Transport icon based on route type
                Image(systemName: iconName(for: bookmark.stop.prioritizedRouteTypeForDisplay))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 32)

                // Bookmark info
                VStack(alignment: .leading, spacing: 2) {
                    Text(bookmark.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    // Show trip info if this is a trip bookmark
                    if bookmark.isTripBookmark, let routeShortName = bookmark.routeShortName, let headsign = bookmark.tripHeadsign {
                        Text("\(routeShortName) - \(headsign)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(bookmark.stop.nameWithLocalizedDirectionAbbreviation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func iconName(for routeType: Route.RouteType) -> String {
        switch routeType {
        case .lightRail: return "tram.fill"
        case .subway: return "tram.fill.tunnel"
        case .rail: return "train.side.front.car"
        case .ferry: return "ferry.fill"
        case .cableCar, .gondola: return "cablecar.fill"
        default: return "bus.fill"
        }
    }
}
