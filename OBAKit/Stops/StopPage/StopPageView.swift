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
    @AppStorage("StopViewController.pastDeparturesCollapsed") private var pastCollapsed = true

    private var filteredDepartures: [ArrivalDeparture] {
        let all = viewModel.stopArrivals?.arrivalsAndDepartures ?? []
        return viewModel.isListFiltered ? all.filter(preferences: viewModel.stopPreferences) : all
    }

    var body: some View {
        List {
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
        }
        .listStyle(.insetGrouped)
        .task { await viewModel.start() }
        .onDisappear { viewModel.deactivate() }
        .refreshable { await viewModel.refresh() }
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
