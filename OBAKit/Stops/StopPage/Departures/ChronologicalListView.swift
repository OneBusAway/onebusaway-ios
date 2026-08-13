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
    let statusProvider: (ArrivalDeparture) -> DepartureStatus
    let alarmLookup: (ArrivalDeparture) -> Alarm?
    let actionsProvider: (ArrivalDeparture) -> DepartureRowActions
    let onSelectDeparture: (ArrivalDeparture) -> Void

    var body: some View {
        // Headerless: the "Arrivals & Departures" title and the Past disclosure
        // that shared its row both moved up to `StopPageListHeaderRow`, which now
        // carries the disclosure beside the mode toggle. This section still owns
        // the past *rows*, which is why it survives at all.
        Section {
            if showPast {
                rows(partition.past, style: .past)
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
                onTap: { onSelectDeparture(departure) }
            )
            .departureRowActions(actions)
        }
    }
}
