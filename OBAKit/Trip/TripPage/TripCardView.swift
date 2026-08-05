//
//  TripCardView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The trip page's header card: which vehicle this is, when it reaches the
/// rider's stop, and how much of that is actually known.
///
/// The badge/headsign/time/status/occupancy row is deliberately the same
/// composition `DepartureRowView` uses — same components, same order — so a
/// departure looks the same after the rider taps it as it did in the list. What
/// this adds is the provenance footer, which only makes sense once you've
/// committed to following one specific vehicle.
struct TripCardView: View {
    /// `nil` for a trip reached from vehicle search, where there is no stop and
    /// so no arrival to count down to.
    let departure: ArrivalDeparture?
    let routeShortName: String
    let headsign: String
    let routeColor: Color
    let routeTextColor: Color?
    let provenance: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.obaFormatters) private var formatters
    @AppStorage(UserDefaultsStore.stopUIReducedColorsKey) private var reducedColors = false

    private var status: DepartureStatus? {
        departure.map { DepartureStatus(arrivalDeparture: $0) }
    }

    /// One construction site for the visible time and the spoken label, so the
    /// two can't drift apart in how they format. Being computed it still runs per
    /// access — this centralises the call, it does not cache it. Mirrors
    /// `DepartureRowView.timeDisplay`.
    private var timeDisplay: DepartureTimeDisplay? {
        departure.map { DepartureTimeDisplay(arrivalDeparture: $0, formatters: formatters) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if dynamicTypeSize.isAccessibilitySize {
                // Same stacking rule as `DepartureRowView`: badge and countdown
                // stay together as glance tokens, everything else flows below.
                HStack(alignment: .center) {
                    badge
                    Spacer(minLength: 8)
                    countdown
                }
                headsignText
                timeAndStatus
                occupancy
            } else {
                HStack(alignment: .top, spacing: 13) {
                    badge
                    VStack(alignment: .leading, spacing: 4) {
                        headsignText
                        timeAndStatus
                        occupancy
                    }
                    Spacer(minLength: 8)
                    countdown
                }
            }

            if let provenance {
                Divider()
                Text(provenance)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        // The card is one fact about one vehicle, so it is one VoiceOver stop —
        // and it has to be, because `RouteBadgeView`, `CountdownView` and
        // `DepartureTimeText` each mark themselves `.accessibilityHidden(true)`
        // on the contract that whatever composes them re-speaks their content.
        // `DepartureRowView` upholds that; this card did not, so the route
        // number, the countdown and the departure time — the three things the
        // page exists to tell you — reached VoiceOver from nowhere at all.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// "Arrives" rather than the departure list's "departs": this card is the one
    /// place the rider is tracking a specific vehicle toward their own stop.
    private var accessibilityText: String {
        guard let departure, let status, let timeDisplay else {
            // Reached from vehicle search: no stop, so no arrival to count down to.
            // Route and headsign are all there is to say.
            let fmt = OBALoc(
                "trip_page.card.a11y_no_arrival_fmt",
                value: "Route %@ to %@",
                comment: "VoiceOver label for the trip page's header card when the trip was reached without a stop, so there is no arrival time."
            )
            return [String(format: fmt, routeShortName, headsign), provenance]
                .compactMap { $0 }
                .joined(separator: ", ")
        }

        // A past departure's `arrivalDepartureMinutes` is negative, and past rows
        // are tappable — `ChronologicalListView` gives them the same `onTap` as
        // reachable ones — so this card is reached for buses that have already
        // gone. Without the branch it announced "arrives in -4 minutes". Reuses
        // the departure list's past sentence rather than adding a fourth key
        // saying the same thing.
        let identity: String
        if departure.arrivalDepartureMinutes < 0 {
            let fmt = OBALoc("stop_page.row.a11y_past_fmt", value: "Route %@ to %@, departed %d minutes ago, %@", comment: "VoiceOver label for a departure row that has already departed: route, headsign, minutes ago, status.")
            identity = String(format: fmt, routeShortName, headsign, abs(departure.arrivalDepartureMinutes), status.accessibilityStatusDescription)
        } else {
            let fmt = OBALoc(
                "trip_page.card.a11y_fmt",
                value: "Route %@ to %@, arrives in %d minutes, %@",
                comment: "VoiceOver label for the trip page's header card: route, headsign, minutes until arrival, status."
            )
            identity = String(format: fmt, routeShortName, headsign, departure.arrivalDepartureMinutes, status.accessibilityStatusDescription)
        }

        return DepartureAccessibility.label(
            identity: identity,
            departure: departure,
            status: status,
            timeDisplay: timeDisplay,
            extraClauses: [provenance].compactMap { $0 }
        )
    }

    private var badge: some View {
        RouteBadgeView(
            routeShortName: routeShortName,
            routeColor: routeColor,
            routeTextColor: routeTextColor,
            reducedColors: reducedColors
        )
    }

    private var headsignText: some View {
        Text(headsign)
            .font(.title3.weight(.bold))
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var timeAndStatus: some View {
        if let status, let timeDisplay {
            HStack(spacing: 6) {
                DepartureTimeText(display: timeDisplay)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("·").foregroundStyle(.tertiary)
                Text(status.label)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(uiColor: status.color))
            }
        }
    }

    @ViewBuilder
    private var occupancy: some View {
        if let status, status.showsOccupancy,
           let occupancy = departure?.occupancyStatus, occupancy != .unknown {
            OccupancyBadge(occupancy: occupancy)
        }
    }

    @ViewBuilder
    private var countdown: some View {
        if let departure, let status {
            CountdownView(
                minutes: departure.arrivalDepartureMinutes,
                isRealTime: status.isRealTime,
                color: Color(uiColor: status.color)
            )
        }
    }
}
