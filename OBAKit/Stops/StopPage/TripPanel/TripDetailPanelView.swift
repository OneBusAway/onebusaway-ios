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
/// `TripPanelActionsRow`) are factored into their own `View` types so SwiftUI can
/// skip re-diffing them when only `tripDetails` changes.
struct TripDetailPanelView: View {
    let departure: ArrivalDeparture
    let status: DepartureStatus
    let alarm: Alarm?
    let alarmLeadTimeMinutes: Int
    let canAlarm: Bool
    /// Changes on each successful stop refresh so the open panel re-fetches its
    /// approach timeline instead of freezing on the first load.
    let refreshToken: Date?
    /// Warm-cache seed, read synchronously from the VM when the panel is built.
    /// With it, the timeline is on screen at full size the frame the accordion
    /// row is inserted, so the insert animation targets the correct final
    /// height instead of the row popping when the async fetch lands.
    let cachedTripDetails: TripDetails?
    let approachLoader: () async -> TripDetails?
    let onSetAlarm: () -> Void
    let onCancelAlarm: () -> Void
    let onChangeAlarm: () -> Void
    /// Region gate (`Region.supportsScheduleForRoute`), matching the row actions:
    /// where route schedules aren't supported, the panel must not offer the flow.
    let canSchedule: Bool
    let onSchedule: () -> Void
    let onBookmark: () -> Void
    let onViewFullTrip: () -> Void

    @State private var tripDetails: TripDetails?
    /// Set when the fetch completes with nothing to show (failed, or the
    /// vehicle is past the approach window) so the pre-allocated skeleton
    /// collapses instead of pulsing forever.
    @State private var timelineUnavailable = false

    /// What the timeline renders: the async fetch result once it lands, else
    /// the synchronous warm-cache seed.
    private var resolvedTripDetails: TripDetails? { tripDetails ?? cachedTripDetails }

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
            if status.isRealTime {
                TripPanelStatusStrip(
                    vehicleID: departure.vehicleID,
                    routeColor: routeColor
                )
            }

            if status.isRealTime {
                liveApproachSection
            } else {
                ScheduledOnlyNotice()
            }

            if canAlarm {
                AlarmControlView(
                    alarmIsSet: alarm != nil,
                    leadTimeMinutes: alarmLeadTimeMinutes,
                    onSet: onSetAlarm,
                    onCancel: onCancelAlarm,
                    onChange: onChangeAlarm
                )
            }

            TripPanelActionsRow(canSchedule: canSchedule, onSchedule: onSchedule, onBookmark: onBookmark, onViewFullTrip: onViewFullTrip)
        }
        .padding(.vertical, 6)
        .task(id: FetchKey(departureID: departure.id, refreshToken: refreshToken)) {
            guard status.isRealTime else { return }
            let details = await approachLoader()
            // A refresh (or a collapse) restarts this task, but the superseded fetch
            // can still land afterwards. Its result belongs to a request nobody is
            // waiting on any more — writing it would clobber the live one, or mark
            // the timeline unavailable while the current fetch is still in flight.
            guard !Task.isCancelled else { return }
            // The skeleton pre-allocates the timeline's slot, so the first
            // result usually swaps in near the same height; animate the small
            // residual adjustment. Refetches swap data in place at the same
            // height and stay non-animated. A nil result while a timeline is
            // showing leaves it in place; nil with only the skeleton showing
            // collapses the slot (§4.1 silently omits the timeline).
            withAnimation(resolvedTripDetails == nil ? .snappy : nil) {
                if let details {
                    tripDetails = details
                } else if resolvedTripDetails == nil {
                    timelineUnavailable = true
                }
            }
        }
    }

    /// Timeline (or its fixed-height skeleton). The skeleton renders from the
    /// panel's very first frame so a real-time panel opens with the timeline's
    /// space already allocated instead of popping taller when the async fetch
    /// lands. Kept in the parent because it reads the panel's state; a fetch
    /// failure or a vehicle that's already past the window collapses to
    /// nothing (silently omitted, §4.1).
    @ViewBuilder
    private var liveApproachSection: some View {
        if let slice = approachSlice {
            ApproachTimelineView(
                rows: timelineRows(slice),
                minutesAway: departure.arrivalDepartureMinutes,
                routeColor: routeColor,
                routeType: departure.route.routeType,
                skippedStopCount: slice.skippedStopCount
            )
        } else if !timelineUnavailable {
            ApproachTimelineSkeleton()
        }
    }

    private var approachSlice: ApproachSlice<TripStopTime>? {
        guard let stopTimes = resolvedTripDetails?.stopTimes else { return nil }
        return ApproachSlice.make(
            stopTimes: stopTimes,
            userStopID: departure.stopID,
            userStopSequence: departure.stopSequence,
            closestStopID: departure.tripStatus?.closestStopID
        )
    }

    private func timelineRows(_ slice: ApproachSlice<TripStopTime>) -> [ApproachTimelineView.Row] {
        slice.stops.enumerated().map { index, stopTime in
            ApproachTimelineView.Row(
                id: "\(index)-\(stopTime.stopID)",
                name: stopTime.stopName,
                isUserStop: index == slice.stops.count - 1,
                isVehicleHere: slice.vehicleIndex == index,
                isPassed: slice.vehicleIndex.map { index <= $0 } ?? false
            )
        }
    }
}

/// Placeholder occupying the approach timeline's slot while the fetch is in
/// flight. Fixed at 150pt so the accordion insert animation targets (roughly)
/// the panel's final height instead of the row popping when the timeline
/// lands. The pulse is gated on Reduce Motion, matching `LiveStatusRow`.
private struct ApproachTimelineSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    /// Deterministic per-row bar widths, echoing the varied stop-name lengths
    /// of the real timeline.
    private static let barWidths: [CGFloat] = [150, 120, 165, 130, 180]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(Self.barWidths.enumerated()), id: \.offset) { _, width in
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .frame(width: 10, height: 10)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .frame(width: width, height: 12)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 150, alignment: .top)
        .opacity(reduceMotion ? 1 : (pulsing ? 0.45 : 1))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
        .accessibilityHidden(true)
    }
}

/// Live-vehicle strip, or the schedule-only strip when there's no real-time
/// position (§4.1). Pure values so it never re-renders on the panel's timeline
/// fetch.
private struct TripPanelStatusStrip: View {
    let vehicleID: String?
    let routeColor: Color

    var body: some View {
        HStack(spacing: 8) {
            RealtimeGlyph(isRealTime: true, color: routeColor, size: 15)
            Text(String(format: OBALoc("stop_page.panel.live_vehicle_fmt", value: "Live · vehicle %@", comment: "Trip panel live strip. %@ is the vehicle id."), vehicleID ?? "—"))
                .font(.footnote.weight(.bold))
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

/// More menu (Add Bookmark / Schedules) + full-trip action, wired to ViewRouter
/// navigation by the hosting page. Half-width side-by-side by default; at
/// accessibility sizes the buttons stack so each is a full-width tap target
/// (the guide's committed layout).
private struct TripPanelActionsRow: View {
    let canSchedule: Bool
    let onSchedule: () -> Void
    let onBookmark: () -> Void
    let onViewFullTrip: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
        layout {
            Menu {
                Button(action: onBookmark) {
                    Label(Strings.addBookmark, systemImage: "bookmark")
                }
                if canSchedule {
                    Button(action: onSchedule) {
                        Label(Strings.schedules, systemImage: "calendar")
                    }
                }
            } label: {
                Label(Strings.more, systemImage: "ellipsis.circle")
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            Button(action: onViewFullTrip) {
                Label(OBALoc("stop_page.panel.full_trip", value: "View full trip", comment: "Opens the full trip screen"), systemImage: "point.bottomleft.forward.to.point.topright.scurvepath")
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(Color(uiColor: ThemeColors.shared.brand))
        .foregroundStyle(.white)
        .font(.body.weight(.semibold))
    }
}
