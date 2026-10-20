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
/// the same `RecentStopsViewModel` the Recent tab uses, alarms first as there.
///
/// The tab's "Find Stops on Maps" empty-state button is dropped: the map is
/// already right behind this sheet.
struct RecentStopsSheetView: View {
    let application: Application

    @StateObject private var viewModel: RecentStopsViewModel
    @EnvironmentObject var coordinator: SheetCoordinator<AppSheetRoute>
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var isConfirmingDeleteAll = false
    /// The alarm whose trip is loading, so a second tap doesn't load it again.
    @State private var openingAlarm: URL?

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

    /// The Recent tab's title for its Alarms section, shared with home's row.
    static var alarmsTitle: String {
        OBALoc("recent_stops_controller.alarms_section.title", value: "Alarms", comment: "Title of the Alarms section of the Recents controller")
    }

    /// The alarms a row can open the trip for, in the store's order. An alarm
    /// stored without its deep link has nowhere to go, as the tab skips it too.
    static func openableAlarms(_ alarms: [Alarm]) -> [(alarm: Alarm, deepLink: ArrivalDepartureDeepLink)] {
        alarms.compactMap { alarm in alarm.deepLink.map { (alarm, $0) } }
    }

    /// Alarms are listed until the rider searches: the query filters stops.
    private var alarms: [(alarm: Alarm, deepLink: ArrivalDepartureDeepLink)] {
        hasActiveQuery ? [] : Self.openableAlarms(viewModel.alarms)
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
                        SheetDismissButton(.close) { dismiss() }
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
        // A fired alarm is deleted from the store.
        .onReceive(NotificationCenter.default.publisher(for: .alarmFired)) { _ in
            viewModel.loadData()
        }
    }

    /// Loads the alarm's arrival and opens its trip over this sheet, as the
    /// Recent tab pushes it.
    private func open(_ deepLink: ArrivalDepartureDeepLink, of alarm: Alarm) {
        guard openingAlarm == nil, let apiService = application.apiService else { return }
        openingAlarm = alarm.url
        Task {
            defer { openingAlarm = nil }
            do {
                let arrival = try await apiService.getTripArrivalDepartureAtStop(deepLink: deepLink).entry
                coordinator.push(.tripDetails(
                    TripConvertible(arrivalDeparture: arrival),
                    destinationStopID: deepLink.destinationStopID
                ))
            } catch {
                await application.displayError(error)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if stops.isEmpty && alarms.isEmpty {
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
                if !alarms.isEmpty {
                    Section(Self.alarmsTitle) {
                        ForEach(alarms, id: \.alarm.url) { item in
                            alarmRow(item.deepLink, of: item.alarm)
                        }
                    }
                }
                Section {
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
                } header: {
                    // Only beside the Alarms section, which needs telling apart.
                    if !alarms.isEmpty, !stops.isEmpty {
                        Text(Strings.recentStops)
                    }
                }
            }
            .searchListChrome()
        }
    }

    private func alarmRow(_ deepLink: ArrivalDepartureDeepLink, of alarm: Alarm) -> some View {
        Button {
            open(deepLink, of: alarm)
        } label: {
            HStack {
                Label(deepLink.title, systemImage: "alarm")
                    .foregroundStyle(Color(uiColor: .label))
                Spacer()
                if openingAlarm == alarm.url {
                    ProgressView()
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button(Strings.delete, role: .destructive) {
                viewModel.delete(alarm: alarm)
            }
        }
    }
}
