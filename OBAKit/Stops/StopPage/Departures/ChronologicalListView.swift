//
//  ChronologicalListView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Temporary stand-in for `TripDetailPanelView` (Task 10). Keeps the accordion
/// mechanics testable in the simulator before the panel exists.
struct TripDetailPanelPlaceholder: View {
    let departure: ArrivalDeparture
    var body: some View {
        Text(departure.routeAndHeadsign)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }
}

/// Chronological mode: past block, missed block, walk divider, reachable
/// block. Rendered as Sections inside StopPageView's single List (each
/// Section is one rounded card in inset-grouped style).
struct ChronologicalListView: View {
    let partition: StopPageListBuilder.ChronologicalPartition<ArrivalDeparture>
    let walkMinutes: Int?
    let showPast: Bool
    let expandedDepartureID: String?
    let statusProvider: (ArrivalDeparture) -> DepartureStatus
    let alarmLookup: (ArrivalDeparture) -> Alarm?
    let actionsProvider: (ArrivalDeparture) -> DepartureRowActions
    let onTogglePast: () -> Void
    let onToggleExpand: (ArrivalDeparture) -> Void
    let panelBuilder: (ArrivalDeparture) -> TripDetailPanelPlaceholder

    var body: some View {
        // Section header with the Past toggle
        Section {
            if showPast {
                rows(partition.past, style: .past)
            }
        } header: {
            HStack {
                Text(OBALoc("stop_page.section.arrivals_departures", value: "Arrivals & Departures", comment: "Chronological list section header"))
                Spacer()
                if !partition.past.isEmpty {
                    Button(action: onTogglePast) {
                        let fmt = OBALoc("stop_page.past_toggle_fmt", value: "Past · %d", comment: "Button revealing recently departed trips. %d is the count.")
                        Text(showPast ? OBALoc("stop_page.past_toggle_hide", value: "Hide past", comment: "Button hiding recently departed trips") : String(format: fmt, partition.past.count))
                            .font(.caption.weight(.bold))
                    }
                }
            }
        }

        if let walkMinutes, !partition.missed.isEmpty {
            Section {
                rows(partition.missed, style: .missed)
            }
            // Walk divider escapes the card chrome (out-of-card row rules).
            Section {
                WalkLineDivider(walkMinutes: walkMinutes)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }

        Section {
            rows(partition.reachable, style: .normal)
        }
    }

    @ViewBuilder
    private func rows(_ departures: [ArrivalDeparture], style: DepartureRowView.Style) -> some View {
        // Identity: ArrivalDeparture.id (stable across prediction refreshes).
        ForEach(departures, id: \.id) { departure in
            DepartureRowView(
                departure: departure,
                status: statusProvider(departure),
                hasAlarm: alarmLookup(departure) != nil,
                style: style,
                onTap: { onToggleExpand(departure) }
            )
            .departureRowActions(actionsProvider(departure))

            // Accordion: the panel is an INSERTED SIBLING ROW, keyed off the
            // expanded id — List animates insert/remove smoothly.
            if expandedDepartureID == departure.id {
                panelBuilder(departure)
            }
        }
    }
}
