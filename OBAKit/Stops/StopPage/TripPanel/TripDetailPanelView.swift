//
//  TripDetailPanelView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The shared "second tap" panel (§4.6), rendered as an inserted row beneath
/// its departure in either mode: live-vehicle strip (or the scheduled-only
/// honesty notice), approach timeline, alarm control, and actions.
///
/// The pure-value header sections (`TripPanelStatusStrip`, `ScheduledOnlyNotice`,
/// `TripPanelActionsRow`) are factored into their own `View` types so the
/// once-per-open `tripDetails` state change only re-renders the timeline
/// section, not the whole panel.
struct TripDetailPanelView: View {
    let departure: ArrivalDeparture
    let status: DepartureStatus
    let alarm: Alarm?
    let alarmLeadTimeMinutes: Int
    let canAlarm: Bool
    /// Changes on each successful stop refresh so the open panel re-fetches its
    /// approach timeline instead of freezing on the first load.
    let refreshToken: Date?
    let approachLoader: () async -> TripDetails?
    let onSetAlarm: () -> Void
    let onCancelAlarm: () -> Void
    let onChangeAlarm: (Int) -> Void
    let onSchedule: () -> Void
    let onViewFullTrip: () -> Void

    @State private var tripDetails: TripDetails?
    @State private var timelineLoading = false

    /// Identity for the timeline `.task`: a change in either the departure or the
    /// refresh token re-runs the fetch. Keeping the token in the key is what lets
    /// an open panel refresh (and lets a nil first fetch retry).
    private struct FetchKey: Hashable {
        let departureID: String
        let refreshToken: Date?
    }

    private var routeColor: Color {
        Color(uiColor: departure.route.color ?? ThemeColors.shared.brand)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TripPanelStatusStrip(
                isRealTime: status.isRealTime,
                vehicleID: departure.vehicleID,
                routeColor: routeColor
            )

            if status.isRealTime {
                liveApproachSection
            } else {
                ScheduledOnlyNotice()
            }

            if canAlarm {
                AlarmControlView(
                    alarmIsSet: alarm != nil,
                    leadTimeMinutes: alarmLeadTimeMinutes,
                    maxLeadTime: AlarmLeadTime.ceiling(minutesUntilDeparture: departure.arrivalDepartureMinutes),
                    onSet: onSetAlarm,
                    onCancel: onCancelAlarm,
                    onChange: onChangeAlarm
                )
            }

            TripPanelActionsRow(onSchedule: onSchedule, onViewFullTrip: onViewFullTrip)
        }
        .padding(.vertical, 6)
        .task(id: FetchKey(departureID: departure.id, refreshToken: refreshToken)) {
            guard status.isRealTime else { return }
            // Show the spinner only on the first load; on a token-driven refetch
            // keep the previous timeline on screen to avoid flicker.
            if tripDetails == nil { timelineLoading = true }
            let details = await approachLoader()
            timelineLoading = false
            // Only swap when the refetch returns data; a nil result (fetch failed
            // or no live timeline) leaves the previously shown timeline in place.
            if let details { tripDetails = details }
        }
    }

    /// Timeline (or its loading spinner). Kept in the parent because it reads the
    /// `tripDetails`/`timelineLoading` state; a fetch failure or a vehicle that's
    /// already past the window renders nothing (silently omitted, §4.1).
    @ViewBuilder
    private var liveApproachSection: some View {
        if let slice = approachSlice {
            ApproachTimelineView(
                rows: timelineRows(slice),
                minutesAway: departure.arrivalDepartureMinutes,
                routeColor: routeColor
            )
        } else if timelineLoading {
            ProgressView().frame(maxWidth: .infinity)
        }
    }

    private var approachSlice: ApproachSlice<TripStopTime>? {
        guard let stopTimes = tripDetails?.stopTimes else { return nil }
        return ApproachSlice.make(
            stopTimes: stopTimes,
            userStopID: departure.stopID,
            closestStopID: departure.tripStatus?.closestStopID
        )
    }

    private func timelineRows(_ slice: ApproachSlice<TripStopTime>) -> [ApproachTimelineView.Row] {
        slice.stops.enumerated().map { index, stopTime in
            ApproachTimelineView.Row(
                id: stopTime.stopID,
                name: stopTime.stopName,
                isUserStop: index == slice.stops.count - 1,
                isVehicleHere: slice.vehicleIndex == index,
                isPassed: slice.vehicleIndex.map { index <= $0 } ?? false
            )
        }
    }
}

/// Live-vehicle strip, or the schedule-only strip when there's no real-time
/// position (§4.1). Pure values so it never re-renders on the panel's timeline
/// fetch.
private struct TripPanelStatusStrip: View {
    let isRealTime: Bool
    let vehicleID: String?
    let routeColor: Color

    var body: some View {
        HStack(spacing: 8) {
            RealtimeGlyph(isRealTime: isRealTime, color: routeColor, size: 15)
            if isRealTime {
                Text(String(format: OBALoc("stop_page.panel.live_vehicle_fmt", value: "Live · vehicle %@", comment: "Trip panel live strip. %@ is the vehicle id."), vehicleID ?? "—"))
                    .font(.footnote.weight(.bold))
            } else {
                Text(OBALoc("stop_page.panel.scheduled_strip", value: "Scheduled · no live position yet", comment: "Trip panel strip for schedule-only trips"))
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The schedule-only honesty notice (§4.1/§4.4): shown instead of the approach
/// timeline when the trip has no live signal, and never alongside occupancy.
private struct ScheduledOnlyNotice: View {
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(OBALoc("stop_page.panel.scheduled_title", value: "Scheduled time only", comment: "Title of the schedule-only notice"))
                    .font(.footnote.weight(.bold))
                Text(OBALoc("stop_page.panel.scheduled_body", value: "No live signal from this bus yet — this is when it's supposed to arrive. It may run early, late, or not at all.", comment: "Body of the schedule-only notice; must communicate uncertainty (§4.1/§4.4)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "calendar").foregroundStyle(.secondary)
        }
    }
}

/// Schedule + full-trip actions. No-op callbacks until Task 12 wires them.
private struct TripPanelActionsRow: View {
    let onSchedule: () -> Void
    let onViewFullTrip: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onSchedule) {
                Label(Strings.schedules, systemImage: "calendar")
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.bordered)
            Button(action: onViewFullTrip) {
                Label(OBALoc("stop_page.panel.full_trip", value: "View full trip", comment: "Opens the full trip screen"), systemImage: "bus")
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.bordered)
        }
    }
}
