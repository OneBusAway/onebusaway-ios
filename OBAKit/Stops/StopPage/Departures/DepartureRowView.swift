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
/// expansion. Unary root HStack; all conditional content is interior so the
/// List fast path holds.
struct DepartureRowView: View {
    enum Style {
        case normal
        /// Upcoming but unreachable on foot: dim + strikethrough (§4.2).
        case missed
        /// Already departed: dim only (§4.2).
        case past
    }

    let departure: ArrivalDeparture
    let status: DepartureStatus
    let hasAlarm: Bool
    var style: Style = .normal
    let onTap: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.obaFormatters) private var formatters

    private var dimmed: Bool { style != .normal }

    private var scheduledTimeText: String {
        formatters.timeFormatter.string(from: departure.scheduledDate)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            RouteBadgeView(
                routeShortName: departure.routeShortName,
                routeColor: Color(uiColor: departure.route.color ?? ThemeColors.shared.brand)
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(departure.tripHeadsign ?? departure.routeShortName)
                    .font(.system(.body, weight: .bold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .strikethrough(style == .missed)
                HStack(spacing: 6) {
                    Text(scheduledTimeText)
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                    Text(status.label)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(uiColor: status.color))
                    if hasAlarm {
                        Image(systemName: "bell.fill")
                            .font(.caption)
                            .foregroundStyle(Color(uiColor: ThemeColors.shared.departureOnTime))
                    }
                }
                if status.showsOccupancy, let occupancy = departure.occupancyStatus, occupancy != .unknown {
                    OccupancyBadge(occupancy: occupancy)
                }
            }
            Spacer(minLength: 8)
            CountdownView(
                minutes: departure.arrivalDepartureMinutes,
                isRealTime: status.isRealTime,
                color: dimmed ? Color(uiColor: .tertiaryLabel) : Color(uiColor: status.color)
            )
        }
        .opacity(dimmed ? 0.55 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
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

/// Swipe + context-menu parity with today's `ArrivalDepartureItem`
/// trailing actions (Alarm / Schedule / Save) and long-press menu.
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
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if actions.canAlarm {
                    Button(action: actions.onAlarmToggle) {
                        Label(actions.hasAlarm ? removeAlarmTitle : Strings.addAlarm, systemImage: actions.hasAlarm ? "bell.slash" : "bell")
                    }
                    .tint(Color(uiColor: ThemeColors.shared.departureOnTime))
                }
                if actions.canSchedule {
                    Button(action: actions.onSchedule) {
                        Label(Strings.schedules, systemImage: "calendar")
                    }
                    .tint(.teal)
                }
                Button(action: actions.onBookmark) {
                    Label(Strings.addBookmark, systemImage: "bookmark")
                }
                .tint(.orange)
            }
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
