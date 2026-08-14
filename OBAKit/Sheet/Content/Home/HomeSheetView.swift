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

    /// Tracks whether the stacked routes were non-empty on the last observation,
    /// so we can detect the transition to empty and re-activate.
    @State private var wasStackedRoutesNonEmpty = false

    /// Needed by `SearchListRow.stop(...)` for distance formatting. Passed in
    /// rather than read from the environment: there is no `Application`
    /// environment key in this codebase, and adding one for a single consumer
    /// would be a wider change than this task warrants. `obaFormatters` (used by
    /// the bookmark rows below) does exist, and is injected from here.
    private let application: Application

    init(
        application: Application,
        viewModel: @autoclosure @escaping () -> HomeSheetViewModel
    ) {
        self.application = application
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                searchBarRow
                    .padding(.top, 16)

                if viewModel.visibleSections.isEmpty {
                    emptyState
                } else {
                    ForEach(viewModel.visibleSections, id: \.self) { section in
                        sectionView(for: section)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .task {
            viewModel.activate()
        }
        .onChange(of: coordinator.stackedRoutes) { _, routes in
            // When a stacked sheet is dismissed and the stack transitions to empty,
            // re-activate the home sheet. This is the moment the user returns to it,
            // and when a new recent stop may have been added.
            let isStackedRoutesNonEmpty = !routes.isEmpty
            if wasStackedRoutesNonEmpty && !isStackedRoutesNonEmpty {
                viewModel.activate()
            }
            wasStackedRoutesNonEmpty = isStackedRoutesNonEmpty
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
    private func sectionView(for section: HomeSheetSection) -> some View {
        switch section {
        case .nearby:
            stopSection(
                title: Strings.nearbyStops,
                stops: viewModel.nearby.stops,
                destination: .nearbyAll,
                kind: { .nearbyStop(id: $0.id) }
            )
        case .recent:
            stopSection(
                title: Strings.recentStops,
                stops: viewModel.recent.stops,
                destination: .recentStopsAll,
                kind: { .recentStop(id: $0.id) }
            )
        case .bookmarks:
            bookmarksSection
        }
    }

    /// Nearby and Recent render identically — same row builder, same layout —
    /// and differ only in title, data, destination, and row kind.
    private func stopSection(
        title: String,
        stops: [Stop],
        destination: AppSheetRoute,
        kind: @escaping (Stop) -> SearchListRow.Kind
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HomeSectionHeader(title: title) {
                coordinator.push(destination)
            }
            ForEach(stops, id: \.id) { stop in
                SearchListRowView(
                    row: SearchListRow.stop(
                        stop,
                        application: application,
                        kind: kind(stop),
                        onSelect: { coordinator.push(.stopDetails(stopID: stop.id)) }
                    )
                )
            }
        }
        .padding(.horizontal, 12)
    }

    private var bookmarksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HomeSectionHeader(title: Strings.bookmarks) {
                coordinator.push(.bookmarksAll)
            }
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
            }
        }
        .padding(.horizontal, 12)
        .environment(\.obaFormatters, application.formatters)
    }

    /// Shown only when all three sections are empty — a first launch, or a map
    /// parked at region-level zoom with no saved data. Reuses the nearby
    /// controller's copy, minus its "Search Wider Area" button: that drives
    /// `MapRegionManager.preferredLoadDataRegionFudgeFactor` and a timed reset
    /// the SwiftUI path has no equivalent plumbing for.
    private var emptyState: some View {
        EmptyStateView(
            title: OBALoc(
                "nearby_controller.empty_set.title",
                value: "No Nearby Stops",
                comment: "Title for the empty set indicator on the Nearby controller"
            ),
            description: OBALoc(
                "nearby_controller.empty_set.body",
                value: "Zoom out or pan around to find some stops.",
                comment: "Body for the empty set indicator on the Nearby controller."
            ),
            systemImage: "mappin.slash"
        )
        .padding(.top, 40)
    }
}
