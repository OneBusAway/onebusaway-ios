//
//  StopPageView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Root view of the redesigned Stop page. This is the ONLY view that observes
/// `StopViewModel`; every subview receives plain values so the VM's frequent
/// `@Published` churn (refresh + status timers) re-evaluates one shallow body.
struct StopPageView: View {
    @ObservedObject var viewModel: StopViewModel

    @State private var expandedDepartureID: String?
    @State private var expandedRouteID: RouteID?
    @State private var didSeedMode = false
    @AppStorage("StopViewController.pastDeparturesCollapsed") private var pastCollapsed = true

    /// Global (not per-stop) "last mode the user picked" seed. A stop the user
    /// has never customized opens in this mode; touched in exactly two places —
    /// read in `seedLastUsedModeIfNeeded()`, written in the toggle's `onChange`.
    private static let lastUsedStopSortKey = "OBALastUsedStopSort"

    private var filteredDepartures: [ArrivalDeparture] {
        let all = viewModel.stopArrivals?.arrivalsAndDepartures ?? []
        return viewModel.isListFiltered ? all.filter(preferences: viewModel.stopPreferences) : all
    }

    var body: some View {
        List {
            Section {
                StopPageModeToggle(mode: viewModel.stopPreferences.sortType) { newValue in
                    withAnimation {
                        // Switching modes collapses every open accordion (§4.6).
                        expandedDepartureID = nil
                        expandedRouteID = nil
                        UserDefaults.standard.set(newValue.rawValue, forKey: Self.lastUsedStopSortKey)
                        viewModel.updateSortType(newValue)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if viewModel.stopPreferences.sortType == .time {
                ChronologicalListView(
                    partition: StopPageListBuilder.chronologicalPartition(filteredDepartures, walkMinutes: viewModel.walkTime?.walkMinutes),
                    walkMinutes: viewModel.walkTime?.walkMinutes,
                    showPast: !pastCollapsed,
                    expandedDepartureID: expandedDepartureID,
                    statusProvider: { DepartureStatus(arrivalDeparture: $0) },
                    alarmLookup: { viewModel.alarm(for: $0) },
                    actionsProvider: makeActions(for:),
                    onTogglePast: { withAnimation { pastCollapsed.toggle() } },
                    onToggleExpand: { departure in
                        withAnimation(.snappy) {
                            expandedDepartureID = expandedDepartureID == departure.id ? nil : departure.id
                        }
                    },
                    panelBuilder: { TripDetailPanelPlaceholder(departure: $0) }
                )
            } else {
                GroupedListView(
                    groups: StopPageListBuilder.routeGroups(filteredDepartures),
                    expandedRouteID: expandedRouteID,
                    openTripDepartureID: expandedDepartureID,
                    statusProvider: { DepartureStatus(arrivalDeparture: $0) },
                    alarmLookup: { viewModel.alarm(for: $0) },
                    alarmLeadTime: { viewModel.alarmLeadTimeMinutes($0) },
                    canAlarm: { viewModel.canCreateAlarm(for: $0) },
                    onToggleRoute: { routeID in
                        withAnimation(.snappy) {
                            expandedRouteID = expandedRouteID == routeID ? nil : routeID
                            expandedDepartureID = nil
                        }
                    },
                    onToggleTrip: { departure in
                        withAnimation(.snappy) {
                            expandedDepartureID = expandedDepartureID == departure.id ? nil : departure.id
                        }
                    },
                    onAlarmToggle: { departure in
                        Task {
                            if viewModel.alarm(for: departure) != nil {
                                await viewModel.cancelAlarm(for: departure)
                            } else {
                                await viewModel.setAlarm(for: departure, leadTimeMinutes: viewModel.defaultAlarmLeadTime)
                            }
                        }
                    },
                    panelBuilder: { TripDetailPanelPlaceholder(departure: $0) }
                )
            }
        }
        .listStyle(.insetGrouped)
        .task { await viewModel.start() }
        .onAppear(perform: seedLastUsedModeIfNeeded)
        .onDisappear { viewModel.deactivate() }
        .refreshable { await viewModel.refresh() }
    }

    /// One-shot: an untouched stop (still on the default `.time` sort) opens in
    /// the last mode the user picked anywhere in the app. A stop with a
    /// persisted `.route` preference is left alone.
    private func seedLastUsedModeIfNeeded() {
        guard !didSeedMode else { return }
        didSeedMode = true
        guard viewModel.stopPreferences.sortType == .time,
              let raw = UserDefaults.standard.string(forKey: Self.lastUsedStopSortKey),
              let seeded = StopSort(rawValue: raw)
        else { return }
        viewModel.updateSortType(seeded)
    }

    private func makeActions(for departure: ArrivalDeparture) -> DepartureRowActions {
        DepartureRowActions(
            canAlarm: viewModel.canCreateAlarm(for: departure),
            canSchedule: false,        // wired in Task 12 (region-gated)
            hasAlarm: viewModel.alarm(for: departure) != nil,
            onAlarmToggle: {
                Task {
                    if viewModel.alarm(for: departure) != nil {
                        await viewModel.cancelAlarm(for: departure)
                    } else {
                        await viewModel.setAlarm(for: departure, leadTimeMinutes: viewModel.defaultAlarmLeadTime)
                    }
                }
            },
            onSchedule: {},            // Task 12
            onBookmark: {},            // Task 12
            onShowTrip: {}             // Task 12
        )
    }
}

/// The segmented Chronological / By route switch shown above the departure list.
/// Factored into its own `View` (per the SwiftUI structure guidance and the
/// Task 9 interface) so `StopPageView` stays a thin composition — the mode
/// change side effects (collapse accordions, persist) live in the caller's
/// `onChange`.
struct StopPageModeToggle: View {
    let mode: StopSort
    let onChange: (StopSort) -> Void

    var body: some View {
        Picker("", selection: Binding(get: { mode }, set: onChange)) {
            Text(OBALoc("stop_page.mode.chronological", value: "Chronological", comment: "Stop page mode toggle: flat time-sorted list")).tag(StopSort.time)
            Text(OBALoc("stop_page.mode.by_route", value: "By route", comment: "Stop page mode toggle: grouped by route")).tag(StopSort.route)
        }
        .pickerStyle(.segmented)
    }
}
