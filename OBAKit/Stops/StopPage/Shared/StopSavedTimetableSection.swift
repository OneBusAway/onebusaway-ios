//
//  StopSavedTimetableSection.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Offline, the stop's saved timetable for the rest of the day, below the
/// saved departures (`StopPageContent.scheduledDepartures`).
///
/// Its rows aren't tappable: a timetable time has no `ArrivalDeparture`
/// behind it, so there is no trip, alarm or bookmark to offer.
///
/// A plain-value view: it never touches `StopViewModel`.
struct StopSavedTimetableSection: View {
    let departures: [ScheduledDeparture]

    /// A timetable time has no prediction, so it reads as schedule data.
    private static let status = DepartureStatus(isRealTime: false, scheduleStatus: .unknown, deviationMinutes: 0)

    var body: some View {
        Section {
            // Offline, every refresh brings back the same timetable, so nothing
            // else redraws these rows as their minutes count down.
            TimelineView(.periodic(from: .now, by: 15)) { _ in
                ForEach(departures.filter { $0.minutes >= 0 }, id: \.self) { departure in
                    StopSavedTimetableRow(departure: departure, status: Self.status)
                }
            }
        } header: {
            Label(Formatters.offlineTimetableText, systemImage: "wifi.slash")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct StopSavedTimetableRow: View {
    let departure: ScheduledDeparture
    let status: DepartureStatus

    @Environment(\.obaFormatters) private var formatters
    @AppStorage(UserDefaultsStore.stopUIReducedColorsKey) private var reducedColors = false
    @AppStorage(UserDefaultsStore.stopTripCompactModeKey) private var compactMode = false

    private var routeName: String {
        departure.route?.shortName ?? departure.routeID
    }

    var body: some View {
        let minutes = max(0, departure.minutes)
        HStack(alignment: .center, spacing: StopTripSpacing.hStack(compactMode)) {
            RouteBadgeView(
                routeShortName: routeName,
                routeColor: Color(uiColor: departure.route?.color ?? ThemeColors.shared.brand),
                routeTextColor: departure.route?.textColor.map { Color(uiColor: $0) },
                reducedColors: reducedColors
            )
            VStack(alignment: .leading, spacing: StopTripSpacing.stack(compactMode)) {
                Text(departure.tripHeadsign)
                    .font(.body.weight(.semibold))
                HStack(spacing: 6) {
                    Text(formatters.timeFormatter.string(from: departure.date))
                    Text("·").foregroundStyle(.tertiary)
                    Text(status.label)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            CountdownView(minutes: minutes, isRealTime: false, color: Color(uiColor: status.color))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([
            routeName,
            departure.tripHeadsign,
            formatters.accessibilityValueForArrivalDeparture(
                arrivalDepartureDate: departure.date,
                arrivalDepartureMinutes: minutes,
                arrivalDepartureStatus: .departing,
                temporalState: minutes == 0 ? .present : .future,
                scheduleStatus: .unknown
            ),
            status.accessibilityStatusDescription
        ].joined(separator: ", "))
    }
}
