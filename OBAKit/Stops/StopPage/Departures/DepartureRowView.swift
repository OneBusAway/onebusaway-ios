//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// `Strings.removeAlarm` doesn't exist yet (only `Strings.addAlarm` does); this
/// row needs both add/remove wording for the alarm toggle, so it's defined
/// locally rather than added to the shared `Strings` catalog.
private let removeAlarmTitle = OBALoc("stop_page.row.remove_alarm", value: "Remove Alarm", comment: "Swipe/context menu action that cancels an existing arrival alarm.")

/// One departure row, used by chronological mode and (compact) by grouped
/// expansion. Unary root VStack; all conditional content (including the
/// accessibility-size layout branch) is interior so the List fast path holds.
struct DepartureRowView: View {
    enum Style {
        case normal
        /// Upcoming but unreachable on foot: rendered like a normal row;
        /// only the VoiceOver label calls it out (§4.2).
        case missed
        /// Already departed: dim only (§4.2).
        case past
    }

    let departure: ArrivalDeparture
    let status: DepartureStatus
    let hasAlarm: Bool
    let canAlarm: Bool
    let onAlarmToggle: () -> Void
    var style: Style = .normal
    let onTap: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.obaFormatters) private var formatters
    @ScaledMetric(relativeTo: .body) private var alarmCircleSize: CGFloat = 34
    @AppStorage(UserDefaultsStore.stopUIReducedColorsKey) private var reducedColors = false

    private var dimmed: Bool { style == .past }

    private var showsAlarmAffordance: Bool { canAlarm || hasAlarm }

    private var scheduledTimeText: String {
        formatters.timeFormatter.string(from: departure.scheduledDate)
    }

    var body: some View {
        // Unary root; the accessibility-size branch is interior so the List
        // fast path holds. At accessibility sizes the row "stacks" (the guide's
        // committed layout): badge + countdown share the first line as glance
        // tokens, destination + status flow below — nothing is dropped.
        VStack(alignment: .leading, spacing: 3) {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .center) {
                    routeBadge
                    Spacer(minLength: 8)
                    alarmCircleButton
                    countdown
                }
                headsignText
                Text(scheduledTimeText)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                statusText
                occupancyBadge
            } else {
                HStack(alignment: .center, spacing: 13) {
                    routeBadge
                    VStack(alignment: .leading, spacing: 3) {
                        headsignText
                        HStack(spacing: 6) {
                            Text(scheduledTimeText)
                                .font(.footnote)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Text("·").foregroundStyle(.tertiary)
                            statusText
                        }
                        occupancyBadge
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .center, spacing: 4) {
                        countdown
                        alarmCircleButton
                    }
                }
            }
        }
        .opacity(dimmed ? 0.55 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityActions {
            if showsAlarmAffordance {
                Button(hasAlarm ? removeAlarmTitle : Strings.addAlarm) {
                    onAlarmToggle()
                }
            }
        }
    }

    // MARK: - Shared pieces (both layouts)

    private var routeBadge: some View {
        RouteBadgeView(
            routeShortName: departure.routeShortName,
            routeColor: Color(uiColor: departure.route.color ?? ThemeColors.shared.brand),
            routeTextColor: departure.route.textColor.map { Color(uiColor: $0) },
            reducedColors: reducedColors
        )
    }

    /// Clamped to two lines at every size (the guide's committed "clamp + tap"
    /// choice): capping row height keeps more departures visible, and tapping
    /// the row opens the trip panel with the full name.
    private var headsignText: some View {
        Text(departure.tripHeadsign ?? departure.routeShortName)
            .font(.system(.body, weight: .bold))
            .lineLimit(2)
    }

    private var statusText: some View {
        Text(status.label)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color(uiColor: status.color))
    }

    @ViewBuilder
    private var alarmCircleButton: some View {
        if showsAlarmAffordance {
            Image(systemName: hasAlarm ? "bell.fill" : "bell")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(hasAlarm ? Color.white : Color.secondary)
                .frame(width: alarmCircleSize, height: alarmCircleSize)
                .background(hasAlarm ? Color(uiColor: ThemeColors.shared.departureOnTime) : Color.clear, in: Circle())
                .overlay(Circle().strokeBorder(Color(uiColor: .separator), lineWidth: hasAlarm ? 0 : 1.5))
                // Use onTapGesture, not Button: inner gestures beat the outer
                // .onTapGesture(perform: onTap) on the row VStack, so tapping the
                // bell fires only the alarm action and never also expands the row.
                // A Button here creates two competing UIGestureRecognizers that enter
                // an infinite resolution loop, pegging the CPU at 100%.
                .onTapGesture { onAlarmToggle() }
        }
    }

    @ViewBuilder
    private var occupancyBadge: some View {
        if status.showsOccupancy, let occupancy = departure.occupancyStatus, occupancy != .unknown {
            OccupancyBadge(occupancy: occupancy)
        }
    }

    private var countdown: some View {
        CountdownView(
            minutes: departure.arrivalDepartureMinutes,
            isRealTime: status.isRealTime,
            color: dimmed ? Color(uiColor: .tertiaryLabel) : Color(uiColor: status.color)
        )
    }

    private var accessibilityText: String {
        var clauses = [baseAccessibilityText]

        if status.showsOccupancy, let occupancy = departure.occupancyStatus, occupancy != .unknown {
            clauses.append(OccupancyBadge.localizedDescription(occupancy))
        }

        if style == .missed {
            clauses.append(OBALoc("stop_page.row.a11y_missed", value: "likely missed — departs sooner than your walk to the stop", comment: "VoiceOver clause appended to a departure row that's upcoming but not reachable on foot before it leaves."))
        }

        if hasAlarm {
            clauses.append(OBALoc("stop_page.row.a11y_alarm_set", value: "alarm set", comment: "VoiceOver suffix indicating a departure alarm is active"))
        }

        return clauses.joined(separator: ", ")
    }

    private var baseAccessibilityText: String {
        switch style {
        case .past:
            let fmt = OBALoc("stop_page.row.a11y_past_fmt", value: "Route %@ to %@, departed %d minutes ago, %@", comment: "VoiceOver label for a departure row that has already departed: route, headsign, minutes ago, status.")
            return String(format: fmt, departure.routeShortName, departure.tripHeadsign ?? "", abs(departure.arrivalDepartureMinutes), status.accessibilityStatusDescription)
        case .normal, .missed:
            let fmt = OBALoc("stop_page.row.a11y_fmt", value: "Route %@ to %@, departs in %d minutes, %@", comment: "VoiceOver label for a departure row: route, headsign, minutes, status.")
            return String(format: fmt, departure.routeShortName, departure.tripHeadsign ?? "", departure.arrivalDepartureMinutes, status.accessibilityStatusDescription)
        }
    }
}

/// Long-press context-menu parity with today's `ArrivalDepartureItem`
/// menu actions (Alarm / Schedule / Save).
struct DepartureRowActions {
    let canAlarm: Bool
    let canSchedule: Bool
    let hasAlarm: Bool
    let onAlarmToggle: () -> Void
    let onSchedule: () -> Void
    let onBookmark: () -> Void
    let onShowTrip: () -> Void
    /// Lazily builds the long-press preview (a `TripViewController` embedded via a
    /// representable). Built by the hosting VC so `Application`/UIKit stay out of
    /// the view layer; `AnyView` is acceptable here because it lives inside the
    /// context menu's lazily-evaluated preview closure, not the row structure.
    let makePreview: () -> AnyView
}

extension View {
    func departureRowActions(_ actions: DepartureRowActions) -> some View {
        self
            .contextMenu(menuItems: {
                Button(action: actions.onShowTrip) {
                    Label(OBALoc("stop_page.row.show_trip", value: "Show Trip Details", comment: "Context menu action opening the full trip screen"), systemImage: "bus")
                }
                if actions.canAlarm {
                    Button(action: actions.onAlarmToggle) {
                        Label(actions.hasAlarm ? removeAlarmTitle : Strings.addAlarm, systemImage: "bell")
                    }
                }
                if actions.canSchedule {
                    Button(action: actions.onSchedule) {
                        Label(Strings.schedules, systemImage: "calendar")
                    }
                }
                Button(action: actions.onBookmark) {
                    Label(Strings.addBookmark, systemImage: "bookmark")
                }
            }, preview: {
                actions.makePreview()
            })
    }
}
