//
//  GroupedListView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Grouped mode: one Section (= one inset-grouped card) per route, ordered by
/// soonest departure (§4.9). Card header is the next departure; expansion
/// lists every loaded departure; tapping one opens the shared trip panel.
///
/// Plain-value view: it never touches `StopViewModel`. Everything it needs
/// arrives as `let` values or closures so `StopPageView` remains the only
/// observer of the view model.
struct GroupedListView: View {
    let groups: [StopPageListBuilder.RouteGroup<ArrivalDeparture>]
    let expandedRouteID: RouteID?
    let openTripDepartureID: String?
    let statusProvider: (ArrivalDeparture) -> DepartureStatus
    let alarmLookup: (ArrivalDeparture) -> Alarm?
    let alarmLeadTime: (Alarm) -> Int
    /// Adaptation to the global alarm-gating constraint: the brief's alarm pill
    /// and row icons ignore `canCreateAlarm(for:)`. This closure lets the view
    /// hide the alarm affordance when a new alarm can't be created — while still
    /// showing it for a departure that already has one, so it can be cancelled.
    let canAlarm: (ArrivalDeparture) -> Bool
    let onToggleRoute: (RouteID) -> Void
    let onToggleTrip: (ArrivalDeparture) -> Void
    let onAlarmToggle: (ArrivalDeparture) -> Void
    let panelBuilder: (ArrivalDeparture) -> TripDetailPanelView

    /// The compact alarm circle in an expanded row. `@ScaledMetric` so the badge
    /// grows with Dynamic Type the same way the 48pt route badge does inside
    /// `RouteBadgeView`.
    @ScaledMetric(relativeTo: .body) private var alarmCircleSize: CGFloat = 34

    @Environment(\.obaFormatters) private var formatters
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(UserDefaultsStore.stopUIReducedColorsKey) private var reducedColors = false

    /// At accessibility sizes the card layouts "stack" (the guide's committed
    /// layout): badge + countdown become glance tokens on the first line and
    /// everything else flows below at full width.
    private var isAccessibilitySize: Bool { dynamicTypeSize.isAccessibilitySize }

    /// Whether this departure should show an alarm affordance: it can take a new
    /// alarm, or it already has one that can be cancelled. Shared by the header
    /// pill, the expanded-row icon, and both VoiceOver custom actions.
    private func showsAlarmAffordance(for departure: ArrivalDeparture) -> Bool {
        canAlarm(departure) || alarmLookup(departure) != nil
    }

    var body: some View {
        // One Section per route — the Section IS the card. Identity is the
        // stable RouteID; the accordion toggle lives INSIDE the Section so the
        // ForEach row stays a single top-level view.
        ForEach(groups, id: \.routeID) { group in
            Section {
                cardHeader(group)
                if expandedRouteID == group.routeID {
                    expandedRows(group)
                }
            }
        }
    }

    // MARK: - Card header (the route's next departure)

    @ViewBuilder
    private func cardHeader(_ group: StopPageListBuilder.RouteGroup<ArrivalDeparture>) -> some View {
        let next = group.next
        let status = statusProvider(next)
        let routeColor = Color(uiColor: next.route.color ?? ThemeColors.shared.brand)
        let alarm = alarmLookup(next)

        VStack(alignment: .leading, spacing: 10) {
            headerPrimaryRow(next: next, status: status, routeColor: routeColor)
            headerChipsRow(group)
        }
        .padding(.vertical, 4)
        .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
        .contentShape(Rectangle())
        .onTapGesture { onToggleRoute(group.routeID) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(groupAccessibilityLabel(group, status: status))
        .accessibilityAddTraits(.isButton)
        // Disclosure state: the card header's activation toggles the list of
        // departures beneath it, so announce which way it will go.
        .accessibilityValue(expandedRouteID == group.routeID
            ? OBALoc("stop_page.grouped.a11y_expanded", value: "expanded", comment: "VoiceOver value of a grouped route card whose departure list is showing.")
            : OBALoc("stop_page.grouped.a11y_collapsed", value: "collapsed", comment: "VoiceOver value of a grouped route card whose departure list is hidden."))
        // The combined element above (`children: .ignore`) swallows the alarm
        // pill Button inside `headerChipsRow`, so VoiceOver can never reach it.
        // `.accessibilityActions` is applied unconditionally (keeping this a
        // single, uninterrupted modifier chain) but its @ContentBuilder body
        // supports `if`, so the custom action itself only exists when the pill
        // would actually be visible — mirroring `alarmPill(for:)`'s own condition.
        .accessibilityActions {
            if showsAlarmAffordance(for: next) {
                Button(alarmActionName(for: alarm)) {
                    onAlarmToggle(next)
                }
            }
        }
    }

    private func alarmActionName(for alarm: Alarm?) -> String {
        alarm != nil
            ? OBALoc("stop_page.grouped.a11y_remove_alarm", value: "Remove alarm", comment: "VoiceOver custom action on a grouped route card's header that cancels the alarm already set for the next departure.")
            : OBALoc("stop_page.grouped.a11y_set_alarm", value: "Set alarm", comment: "VoiceOver custom action on a grouped route card's header that creates an alarm for the next departure.")
    }

    /// Badge, headsign, scheduled time + adherence, and the big countdown.
    /// At accessibility sizes the badge and countdown become glance tokens on
    /// the first line, with the headsign and time/status stacked below.
    private func headerPrimaryRow(next: ArrivalDeparture, status: DepartureStatus, routeColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if isAccessibilitySize {
                HStack(alignment: .center) {
                    routeBadge(for: next, routeColor: routeColor)
                    Spacer(minLength: 8)
                    CountdownView(minutes: next.arrivalDepartureMinutes, isRealTime: status.isRealTime, color: Color(uiColor: status.color))
                }
                headsignText(next)
                Text(formatters.timeFormatter.string(from: next.scheduledDate))
                    .font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                Text(status.label)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(uiColor: status.color))
            } else {
                HStack(alignment: .center, spacing: 13) {
                    routeBadge(for: next, routeColor: routeColor)
                    VStack(alignment: .leading, spacing: 3) {
                        headsignText(next)
                        HStack(spacing: 6) {
                            Text(formatters.timeFormatter.string(from: next.scheduledDate))
                                .font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                            Text("·").foregroundStyle(.tertiary)
                            Text(status.label)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color(uiColor: status.color))
                        }
                    }
                    Spacer(minLength: 8)
                    CountdownView(minutes: next.arrivalDepartureMinutes, isRealTime: status.isRealTime, color: Color(uiColor: status.color))
                }
            }
        }
    }

    private func routeBadge(for next: ArrivalDeparture, routeColor: Color) -> some View {
        RouteBadgeView(
            routeShortName: next.routeShortName,
            routeColor: routeColor,
            routeTextColor: next.route.textColor.map { Color(uiColor: $0) },
            size: 48,
            reducedColors: reducedColors
        )
    }

    /// Clamped to two lines at every size (the guide's committed "clamp + tap"
    /// choice); expanding the card reveals rows that lead to the full name.
    private func headsignText(_ next: ArrivalDeparture) -> some View {
        Text(next.tripHeadsign ?? next.routeShortName)
            .font(.headline.weight(.heavy))
            .lineLimit(2)
    }

    /// Upcoming-trip chips (each tinted by its own departure's status), the
    /// alarm pill, and the expand chevron. At accessibility sizes the chips
    /// wrap in a flow under a "Next departures" caption (their meaning is no
    /// longer inferable from proximity alone) and the alarm pill + chevron
    /// drop to their own full-width line.
    @ViewBuilder
    private func headerChipsRow(_ group: StopPageListBuilder.RouteGroup<ArrivalDeparture>) -> some View {
        if isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                if !group.chips.isEmpty {
                    Text(OBALoc("stop_page.grouped.next_departures", value: "Next departures", comment: "Caption above the upcoming-departure minute chips on a grouped route card at accessibility text sizes."))
                        .textCase(.uppercase)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    FlowLayout(hSpacing: 8, vSpacing: 8) {
                        chips(group)
                    }
                }
                HStack(spacing: 8) {
                    alarmPill(for: group.next)
                    Spacer()
                    expandChevron(group)
                }
            }
        } else {
            HStack(spacing: 8) {
                chips(group)
                Spacer()
                alarmPill(for: group.next)
                expandChevron(group)
            }
        }
    }

    private func chips(_ group: StopPageListBuilder.RouteGroup<ArrivalDeparture>) -> some View {
        ForEach(group.chips, id: \.id) { chip in
            let chipStatus = statusProvider(chip)
            Text("\(chip.arrivalDepartureMinutes)m")
                .font(.caption.weight(.heavy)).monospacedDigit()
                .foregroundStyle(Color(uiColor: chipStatus.color))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color(uiColor: chipStatus.color).opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func expandChevron(_ group: StopPageListBuilder.RouteGroup<ArrivalDeparture>) -> some View {
        Image(systemName: "chevron.down")
            .font(.footnote.weight(.bold))
            .foregroundStyle(.tertiary)
            .rotationEffect(.degrees(expandedRouteID == group.routeID ? 180 : 0))
    }

    @ViewBuilder
    private func alarmPill(for departure: ArrivalDeparture) -> some View {
        let alarm = alarmLookup(departure)
        if showsAlarmAffordance(for: departure) {
            Button {
                onAlarmToggle(departure)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: alarm != nil ? "bell.fill" : "bell")
                    Text(alarm.map { "\(alarmLeadTime($0))m" } ?? Strings.alarm)
                        .monospacedDigit()
                }
                .font(.caption.weight(.heavy))
                .foregroundStyle(alarm != nil ? Color.white : Color.secondary)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(alarm != nil ? Color(uiColor: ThemeColors.shared.departureOnTime) : Color(uiColor: .tertiarySystemFill), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Expanded rows

    @ViewBuilder
    // swiftlint:disable:next function_body_length
    private func expandedRows(_ group: StopPageListBuilder.RouteGroup<ArrivalDeparture>) -> some View {
        ForEach(group.departures, id: \.id) { departure in
            let status = statusProvider(departure)
            // Unary root; the accessibility-size branch stacks the row the
            // same way the departure rows do — glance tokens (alarm circle,
            // countdown, chevron) on the first line, time + status below.
            VStack(alignment: .leading, spacing: 4) {
                if isAccessibilitySize {
                    HStack(spacing: 12) {
                        alarmIcon(for: departure)
                        Spacer(minLength: 8)
                        CountdownView(minutes: departure.arrivalDepartureMinutes, isRealTime: status.isRealTime, color: Color(uiColor: status.color), emphasized: false)
                        tripChevron(departure)
                    }
                    Text(formatters.timeFormatter.string(from: departure.scheduledDate))
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                    Text(status.label)
                        .font(.subheadline)
                        .foregroundStyle(Color(uiColor: status.color))
                    if status.showsOccupancy, let occupancy = departure.occupancyStatus, occupancy != .unknown {
                        OccupancyBadge(occupancy: occupancy)
                    }
                } else {
                    HStack(spacing: 12) {
                        alarmIcon(for: departure)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(formatters.timeFormatter.string(from: departure.scheduledDate))
                                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                                Text("· \(status.label)")
                                    .font(.subheadline)
                                    .foregroundStyle(Color(uiColor: status.color))
                            }
                            if status.showsOccupancy, let occupancy = departure.occupancyStatus, occupancy != .unknown {
                                OccupancyBadge(occupancy: occupancy)
                            }
                        }
                        Spacer(minLength: 8)
                        CountdownView(minutes: departure.arrivalDepartureMinutes, isRealTime: status.isRealTime, color: Color(uiColor: status.color), emphasized: false)
                        tripChevron(departure)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onToggleTrip(departure) }
            .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
            // Make the whole expanded row a single VoiceOver activation target
            // that opens the trip panel, mirroring the card
            // header (`children: .ignore` + explicit label + `.isButton`). The
            // combined element swallows the inner alarm Button, so it's re-exposed
            // as a custom action just like the header's alarm pill.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(expandedRowAccessibilityLabel(departure, status: status))
            .accessibilityAddTraits(.isButton)
            .accessibilityActions {
                if showsAlarmAffordance(for: departure) {
                    Button(alarmActionName(for: alarmLookup(departure))) {
                        onAlarmToggle(departure)
                    }
                }
            }

            // Accordion: the trip panel is an INSERTED SIBLING ROW keyed off the
            // open id — List animates the insert/remove.
            if openTripDepartureID == departure.id {
                panelBuilder(departure)
                    .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
            }
        }
    }

    private func tripChevron(_ departure: ArrivalDeparture) -> some View {
        Image(systemName: "chevron.down")
            .font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            .rotationEffect(.degrees(openTripDepartureID == departure.id ? 180 : 0))
    }

    @ViewBuilder
    private func alarmIcon(for departure: ArrivalDeparture) -> some View {
        let alarm = alarmLookup(departure)
        if showsAlarmAffordance(for: departure) {
            Button { onAlarmToggle(departure) } label: {
                Image(systemName: alarm != nil ? "bell.fill" : "bell")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(alarm != nil ? Color.white : Color.secondary)
                    .frame(width: alarmCircleSize, height: alarmCircleSize)
                    .background(alarm != nil ? Color(uiColor: ThemeColors.shared.departureOnTime) : Color.clear, in: Circle())
                    .overlay(Circle().strokeBorder(Color(uiColor: .separator), lineWidth: alarm != nil ? 0 : 1.5))
            }
            .buttonStyle(.plain)
        }
    }

    /// Self-describing VoiceOver label for one expanded departure row: route,
    /// headsign, minutes, live/scheduled status, and occupancy when present.
    private func expandedRowAccessibilityLabel(_ departure: ArrivalDeparture, status: DepartureStatus) -> String {
        let fmt = OBALoc("stop_page.grouped.expanded_row.a11y_fmt", value: "Route %@ to %@, departs in %d minutes, %@", comment: "VoiceOver label for one expanded departure row inside a grouped route card: route, headsign, minutes, status.")
        var label = String(format: fmt, departure.routeShortName, departure.tripHeadsign ?? "", departure.arrivalDepartureMinutes, status.accessibilityStatusDescription)
        if status.showsOccupancy, let occupancy = departure.occupancyStatus, occupancy != .unknown {
            label += ", " + OccupancyBadge.localizedDescription(occupancy)
        }
        return label
    }

    private func groupAccessibilityLabel(_ group: StopPageListBuilder.RouteGroup<ArrivalDeparture>, status: DepartureStatus) -> String {
        let fmt = OBALoc("stop_page.grouped.a11y_fmt", value: "Route %@ to %@, next departure in %d minutes, %@. %d more departures loaded.", comment: "VoiceOver label for a grouped route card")
        return String(format: fmt, group.next.routeShortName, group.next.tripHeadsign ?? "", group.next.arrivalDepartureMinutes, status.accessibilityStatusDescription, group.upcoming.count)
    }
}
