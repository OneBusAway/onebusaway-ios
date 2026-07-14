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
    let panelBuilder: (ArrivalDeparture) -> TripDetailPanelView

    var body: some View {
        // Section header with the Past toggle
        Section {
            if showPast {
                rows(partition.past, style: .past)
            }
        } header: {
            HStack {
                Text(OBALoc("stop_page.section.arrivals_departures", value: "Arrivals & Departures", comment: "Chronological list section header"))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if !partition.past.isEmpty {
                    Button(action: onTogglePast) {
                        let fmt = OBALoc("stop_page.past_toggle_fmt", value: "Past · %d", comment: "Button revealing recently departed trips. %d is the count.")
                        Text(showPast ? OBALoc("stop_page.past_toggle_hide", value: "Hide past", comment: "Button hiding recently departed trips") : String(format: fmt, partition.past.count))
                            .font(.caption.weight(.bold))
                    }
                    // The visible "Past · 3" is a glanceable token; spoken
                    // aloud it needs to say what activating actually does.
                    .accessibilityLabel(showPast
                        ? OBALoc("stop_page.past_toggle_hide_a11y", value: "Hide past departures", comment: "VoiceOver label for the button hiding recently departed trips")
                        : String(format: OBALoc("stop_page.past_toggle_show_a11y_fmt", value: "Show %d past departures", comment: "VoiceOver label for the button revealing recently departed trips. %d is the count. Plural forms live in Localizable.stringsdict; the value above is only the not-found fallback."), partition.past.count))
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
            let actions = actionsProvider(departure)
            DepartureRowView(
                departure: departure,
                status: statusProvider(departure),
                hasAlarm: alarmLookup(departure) != nil,
                canAlarm: actions.canAlarm,
                onAlarmToggle: actions.onAlarmToggle,
                style: style,
                onTap: { onToggleExpand(departure) }
            )
            .departureRowActions(actions)

            // Accordion: the panel is an INSERTED SIBLING ROW, keyed off the
            // expanded id — List animates insert/remove smoothly.
            if expandedDepartureID == departure.id {
                panelBuilder(departure)
            }
        }
    }
}
