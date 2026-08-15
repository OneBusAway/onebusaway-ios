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
        let normalized = String.nilifyBlankValue(
            query?.localizedLowercase.trimmingCharacters(in: .whitespacesAndNewlines)
        ) ?? nil
        return stops.filter { $0.matchesQuery(normalized) }
    }

    private var stops: [Stop] {
        Self.filter(stops: viewModel.recentStops, query: searchText)
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
    }

    @ViewBuilder
    private var content: some View {
        if stops.isEmpty {
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
