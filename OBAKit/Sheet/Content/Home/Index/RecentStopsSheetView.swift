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

/// The Recent Stops index: the home sheet's Recent tab, and
/// `AppSheetRoute.recentStopsAll` where the sheet has no tabs.
///
/// As a tab it is laid out like Home: a section title on the search field's
/// edge, the rows under it, and Clear Recent Stops after the last. It has no
/// search field of its own; the sheet's finds stops. Alarms are on Home.
///
/// The UIKit tab's "Find Stops on Maps" empty-state button is dropped: the map
/// is already right behind this sheet.
struct RecentStopsSheetView: View {
    let application: Application

    @StateObject private var viewModel: RecentStopsViewModel
    @EnvironmentObject var coordinator: SheetCoordinator<AppSheetRoute>
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isHomeSheetTab) private var isHomeSheetTab

    @State private var isConfirmingDeleteAll = false

    init(application: Application) {
        self.application = application
        _viewModel = StateObject(wrappedValue: RecentStopsViewModel(application: application))
    }

    var body: some View {
        content
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
            .recentStopBookmarkPrompts(viewModel: viewModel)
            .task { viewModel.loadData(includesAlarms: false) }
            .onChange(of: coordinator.stackedRoutes.count) { previousCount, count in
                // Reload when a sheet stacked *above* this one goes away. Tapping a row
                // pushes `.stopDetails`, which `prefersStacking` puts on the stacked
                // layer — this view is never removed from the hierarchy, so `.task`
                // never runs again. Meanwhile viewing a stop calls `addRecentStop`, so
                // by the time the user drags that sheet away the store has reordered
                // and this list has not.
                guard StackedSheetReturn.wasUncovered(previousDepth: previousCount, depth: count) else { return }
                viewModel.loadData(includesAlarms: false)
            }
    }

    /// As a tab, the list under the home sheet's search field and tab bar. Over
    /// the sheet, the same list with a title and a close button above it.
    @ViewBuilder
    private var content: some View {
        if isHomeSheetTab {
            list
        } else {
            NavigationStack {
                list
                    .navigationTitle(Text(Strings.recentStops))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            SheetDismissButton(.close) { dismiss() }
                        }
                    }
            }
        }
    }

    private var list: some View {
        List {
            Section {
                if viewModel.recentStops.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(viewModel.recentStops, id: \.id) { stop in
                        HomeStopRow(stop: stop) {
                            coordinator.push(.stopDetails(stopID: stop.id))
                        }
                        .recentStopSwipeActions(for: stop, viewModel: viewModel)
                    }
                    .homeRowInsets()
                }
            } header: {
                // Over the sheet, the navigation bar has the title.
                if isHomeSheetTab {
                    HomeSectionTitle(title: Strings.recentStops)
                        .homeHeaderInsets()
                }
            }
            .textCase(nil)

            if !viewModel.recentStops.isEmpty {
                clearButton
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .searchListChrome(horizontalMargin: HomeTabs.horizontalMargin)
    }

    /// After the last stop rather than in a toolbar: the tab has no navigation
    /// bar, and clearing every recent stop is not something to keep in reach.
    private var clearButton: some View {
        Button(OBALoc(
            "recent_stops.clear_all",
            value: "Clear Recent Stops",
            comment: "A button below the list of recent stops that deletes all of them, after asking."
        )) {
            isConfirmingDeleteAll = true
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(Color(uiColor: ThemeColors.shared.brandAccent))
        .fontWeight(.semibold)
    }

    private var emptyState: some View {
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
            systemImage: AppSymbol.recent
        )
        .padding(.top, 40)
    }
}
