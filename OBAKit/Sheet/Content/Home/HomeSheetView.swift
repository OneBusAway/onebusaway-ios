//
//  HomeSheetView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

struct HomeSheetView: View {
    @StateObject private var viewModel: HomeSheetViewModel
    @EnvironmentObject var coordinator: SheetCoordinator<AppSheetRoute>

    /// Used by the bookmark rows to format distances.
    private let application: Application

    init(
        application: Application,
        viewModel: @autoclosure @escaping () -> HomeSheetViewModel
    ) {
        self.application = application
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBarRow
                .padding(.top, 16)
                .padding(.bottom, 12)

            if !viewModel.visibleSections.isEmpty {
                List {
                    ForEach(viewModel.visibleSections, id: \.self) { section in
                        sectionContent(for: section)
                    }
                }
                // Applied to the `List`, matching `BookmarksListView`, rather than
                // to the bookmarks `Section` alone.
                .environment(\.obaFormatters, application.formatters)
                .searchListChrome()
            } else if viewModel.hasLoadedInitialContent {
                emptyState
            } else {
                // Pre-first-settle: nearby hasn't had its chance yet, so "empty"
                // isn't a fact. Hold the space rather than flash a wrong answer.
                Spacer()
            }
        }
        .searchSheetBackground()
        .ignoresSafeArea(.container, edges: .bottom)
        .task {
            viewModel.activate()
        }
        .onChange(of: coordinator.stackedRoutes) { previousRoutes, routes in
            // Re-activate when the stacked layer transitions to empty — the moment the
            // user returns to the home sheet, and when a recent stop may have been added.
            // Derived from `onChange`'s previous value rather than tracked in `@State`:
            // the sheet system can rebuild this view's content while a stacked sheet is
            // open, which would re-seed a stored flag and silently skip the next refresh.
            if !previousRoutes.isEmpty && routes.isEmpty {
                viewModel.activate()
            }
        }
    }

    // MARK: - Search Bar

    private var searchBarRow: some View {
        Button {
            coordinator.push(.search)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text(viewModel.searchPlaceholder)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background { Capsule().fill(Color(.tertiarySystemFill)) }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
    }

    // MARK: - Sections

    @ViewBuilder
    private func sectionContent(for section: HomeSheetSection) -> some View {
        switch section {
        case .nearby:
            stopSection(
                stops: viewModel.nearby.stops,
                title: Strings.nearbyStops,
                seeAll: .nearbyAll
            )

        case .recent:
            stopSection(
                stops: viewModel.recent.stops,
                title: Strings.recentStops,
                seeAll: .recentStopsAll
            )

        case .bookmarks:
            bookmarksSection
        }
    }

    /// The nearby and recent sections: same row and header shape, different
    /// source and destination.
    private func stopSection(
        stops: [Stop],
        title: String,
        seeAll: AppSheetRoute
    ) -> some View {
        Section {
            ForEach(stops, id: \.id) { stop in
                HomeStopRow(stop: stop) {
                    coordinator.push(.stopDetails(stopID: stop.id))
                }
            }
        } header: {
            HomeSectionHeader(title: title) {
                coordinator.push(seeAll)
            }
        }
        .textCase(nil)
    }

    /// Bookmark rows reuse the Bookmarks tab's cells as-is, so the two surfaces
    /// can't drift apart visually.
    private var bookmarksSection: some View {
        Section {
            ForEach(viewModel.bookmarks.rows) { row in
                Group {
                    if row.isTripBookmark {
                        BookmarkCardView(row: row)
                    } else {
                        StopBookmarkRow(row: row)
                    }
                }
                .contentShape(.rect)
                .onTapGesture {
                    coordinator.push(.stopDetails(stopID: row.stopID))
                }
                .contextMenu {
                    // Pinning is reachable from the row it affects, not only from
                    // the Bookmarks tab — this section is where the result shows.
                    BookmarkPinButton(isPinned: row.isPinned) {
                        viewModel.bookmarks.togglePin(row.bookmark)
                    }
                }
            }
        } header: {
            HomeSectionHeader(title: Strings.bookmarks) {
                coordinator.push(.bookmarksAll)
            }
        }
        .textCase(nil)
    }

    /// Shown only when all three sections are empty at once — a first launch, or
    /// a map parked at region-level zoom with nothing saved.
    ///
    /// Has its own copy rather than reusing the nearby controller's: two of the
    /// three sections have nothing to do with the map, so "Zoom out or pan around
    /// to find some stops" would be advice that can't fix what the user is
    /// actually missing.
    ///
    /// Deliberately omits the nearby controller's "Search Wider Area" button: that
    /// drives `MapRegionManager.preferredLoadDataRegionFudgeFactor` and a timed
    /// reset the SwiftUI path has no equivalent plumbing for.
    private var emptyState: some View {
        EmptyStateView(
            title: OBALoc(
                "home_sheet.empty_set.title",
                value: "Nothing Here Yet",
                comment: "Title for the home sheet's empty state, shown when there are no nearby stops, no recent stops, and no bookmarks."
            ),
            description: OBALoc(
                "home_sheet.empty_set.body",
                value: "Nearby stops, stops you've viewed, and your bookmarks will show up here.",
                comment: "Body for the home sheet's empty state, shown when there are no nearby stops, no recent stops, and no bookmarks."
            ),
            systemImage: "mappin.slash"
        )
        .padding(.top, 40)
    }
}
