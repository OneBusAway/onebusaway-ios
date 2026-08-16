//
//  RecentStopsSheetView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The Recent Stops index — `AppSheetRoute.recentStopsAll`. A native list over
/// the same `RecentStopsViewModel` the Recent tab uses.
///
/// The tab's Alarms section is deliberately absent: the home sheet's header
/// promises recent *stops*, and alarm deep-links have no place in the sheet
/// stack. The tab's "Find Stops on Maps" empty-state button is dropped too —
/// the map is already right behind this sheet.
struct RecentStopsSheetView: View {
    let application: Application

    @StateObject private var viewModel: RecentStopsViewModel
    @EnvironmentObject var coordinator: SheetCoordinator<AppSheetRoute>
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var isConfirmingDeleteAll = false

    init(application: Application) {
        self.application = application
        _viewModel = StateObject(wrappedValue: RecentStopsViewModel(application: application))
    }

    /// Applies the search field's query, preserving the store's
    /// most-recently-used ordering. A nil, blank, or whitespace-only query
    /// matches everything — `.searchable` hands the view "" on focus.
    ///
    /// Static and pure so the rule is assertable without a view.
    static func filter(stops: [Stop], query: String?) -> [Stop] {
        let normalized = String.normalizedSearchQuery(query)
        return stops.filter { $0.matchesQuery(normalized) }
    }

    private var stops: [Stop] {
        Self.filter(stops: viewModel.recentStops, query: searchText)
    }

    /// Whether the user has actually typed something to filter by, as opposed to
    /// merely focusing the field. Drives the choice between the "no recents yet"
    /// empty state and a no-search-results one.
    private var hasActiveQuery: Bool {
        String.normalizedSearchQuery(searchText) != nil
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text(Strings.recentStops))
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $searchText)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(Strings.close) { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(OBALoc(
                            "recent_stops.delete_all",
                            value: "Delete All",
                            comment: "A button that deletes all of the recent stops in the app."
                        ), role: .destructive) {
                            isConfirmingDeleteAll = true
                        }
                        .disabled(viewModel.recentStops.isEmpty)
                    }
                }
                .confirmationDialog(
                    OBALoc(
                        "recent_stops.confirmation_alert.title",
                        value: "Are you sure you want to delete all of your recent stops?",
                        comment: "Title for a confirmation alert displayed before the user deletes all of their recent stops."
                    ),
                    isPresented: $isConfirmingDeleteAll,
                    titleVisibility: .visible
                ) {
                    Button(Strings.delete, role: .destructive) {
                        viewModel.deleteAllRecentStops()
                    }
                    Button(Strings.cancel, role: .cancel) { }
                }
        }
        .searchSheetBackground()
        .task { viewModel.loadData() }
        .onChange(of: coordinator.stackedRoutes.count) { previousCount, count in
            // Reload when a sheet stacked *above* this one goes away. Tapping a row
            // pushes `.stopDetails`, which `prefersStacking` puts on the stacked
            // layer — this view is never removed from the hierarchy, so `.task`
            // never runs again. Meanwhile viewing a stop calls `addRecentStop`, so
            // by the time the user drags that sheet away the store has reordered
            // and this list has not.
            guard StackedSheetReturn.wasUncovered(previousDepth: previousCount, depth: count) else { return }
            viewModel.loadData()
        }
    }

    @ViewBuilder
    private var content: some View {
        if stops.isEmpty {
            if hasActiveQuery {
                // A search that matched nothing is not an empty list: telling the
                // user their viewed stops "will appear here" when they're staring
                // at a query that didn't match describes the wrong problem.
                // `ContentUnavailableView.search` is the system's own phrasing,
                // localized by the OS and quoting the query back.
                ContentUnavailableView.search(text: searchText)
            } else {
                EmptyStateView(
                    title: OBALoc(
                        "recent_stops.empty_set.title",
                        value: "No Recent Stops",
                        comment: "Title for the empty set indicator on the Recent Stops controller."
                    ),
                    description: OBALoc(
                        "recent_stops.empty_set.body",
                        value: "Transit stops that you view in the app will appear here.",
                        comment: "Body for the empty set indicator on the Recent Stops controller."
                    ),
                    systemImage: AppSymbol.search
                )
            }
        } else {
            List {
                ForEach(stops, id: \.id) { stop in
                    HomeStopRow(stop: stop) {
                        coordinator.push(.stopDetails(stopID: stop.id))
                    }
                    .swipeActions(edge: .trailing) {
                        Button(Strings.delete, role: .destructive) {
                            viewModel.delete(recentStop: stop)
                        }
                    }
                }
            }
            .searchListChrome()
        }
    }
}
