//
//  BookmarkCardView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Trip-bookmark row, laid out like a departure board: route badge, then the
/// bookmark name and "time · adherence" line, then a trailing column with the
/// countdown over the upcoming-departure chips, so the minutes line up down the
/// list. The pieces are the Stop page's grouped route card header's
/// (`RouteBadgeView`, `DepartureTimeText`, `CountdownView`, the chips).
struct BookmarkCardView: View {
    let row: BookmarkRowViewModel

    @Environment(\.obaFormatters) private var formatters
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var flashing = false
    @State private var flashDismissal: Task<Void, Never>?
    /// Snapshot of the trip IDs that triggered the current flash. The row is
    /// rebuilt once per bookmark fetch, and rebuilds triggered by *other*
    /// bookmarks reset `row.highlightedTripIDs` to empty — without this
    /// snapshot, those unrelated rebuilds would cut the 2-second flash short.
    @State private var flashedTripIDs: Set<TripIdentifier> = []

    private var isAccessibilitySize: Bool { typeSize.isAccessibilitySize }

    private var primary: ArrivalDeparture? { row.upcomingArrivalDepartures.first }
    private var chips: [ArrivalDeparture] { Array(row.upcomingArrivalDepartures.dropFirst().prefix(2)) }

    /// Offline, once the saved real-time departures are gone: the timetable's
    /// next departure and the two after it stand in for `primary` and `chips`.
    private var scheduledPrimary: ScheduledDeparture? { row.upcomingScheduledDepartures.first }
    private var scheduledChips: [ScheduledDeparture] { Array(row.upcomingScheduledDepartures.dropFirst().prefix(2)) }

    /// A timetable time has no prediction, so it reads as schedule data.
    private static let timetableStatus = DepartureStatus(isRealTime: false, scheduleStatus: .unknown, deviationMinutes: 0)

    private var routeColor: Color {
        Color(uiColor: primary?.route.color ?? scheduledPrimary?.route?.color ?? ThemeColors.shared.brand)
    }

    var body: some View {
        if row.savedArrivalsDate != nil {
            // Offline, a refresh brings back the same saved or timetable
            // departures, so nothing else redraws the card as their minutes
            // count down.
            TimelineView(.periodic(from: .now, by: 15)) { _ in
                card
            }
        } else {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isAccessibilitySize {
                accessibilityPrimaryRow
                // Accessibility sizes have no room for a trailing column, so
                // the chips keep their own row there.
                if !chips.isEmpty {
                    FlowLayout(hSpacing: 8, vSpacing: 8) {
                        chipViews
                    }
                } else if !scheduledChips.isEmpty {
                    FlowLayout(hSpacing: 8, vSpacing: 8) {
                        scheduledChipViews
                    }
                }
            } else {
                primaryRow
            }
        }
        .onAppear { flashIfNeeded() }
        .onChange(of: row.highlightedTripIDs) { flashIfNeeded() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel(base: formatters.accessibilityLabel(for: row)))
        .accessibilityValue(formatters.accessibilityValue(for: row) ?? "")
        .accessibilityIdentifier("bookmark_row")
        .accessibilityAddTraits([.isButton, .updatesFrequently])
    }

    // MARK: - Primary Row

    private var primaryRow: some View {
        HStack(alignment: .center, spacing: 12) {
            RouteBadgeView(
                routeShortName: row.routeShortName ?? row.name,
                routeColor: routeColor
            )
            VStack(alignment: .leading, spacing: 3) {
                nameText
                statusLine
                destinationLine
                savedArrivalsLine
            }
            Spacer(minLength: 8)
            if let primary {
                VStack(alignment: .trailing, spacing: 6) {
                    countdownBadge(for: primary)
                    if !chips.isEmpty {
                        HStack(spacing: 5) {
                            chipViews
                        }
                    }
                }
                .fixedSize()
            } else if let scheduledPrimary {
                VStack(alignment: .trailing, spacing: 6) {
                    scheduledCountdown(for: scheduledPrimary)
                    if !scheduledChips.isEmpty {
                        HStack(spacing: 5) {
                            scheduledChipViews
                        }
                    }
                }
                .fixedSize()
            }
        }
    }

    /// Accessibility-size layout mirroring `GroupedListView.headerPrimaryRow`:
    /// badge and countdown become glance tokens on the first line, with the
    /// name, time, and adherence stacked below.
    private var accessibilityPrimaryRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center) {
                RouteBadgeView(
                    routeShortName: row.routeShortName ?? row.name,
                    routeColor: routeColor
                )
                Spacer(minLength: 8)
                if let primary {
                    countdownBadge(for: primary)
                } else if let scheduledPrimary {
                    scheduledCountdown(for: scheduledPrimary)
                }
            }
            nameText
            if let primary {
                timeText(DepartureTimeDisplay(arrivalDeparture: primary, formatters: formatters))
                statusText(for: DepartureStatus(arrivalDeparture: primary))
            } else if let scheduledPrimary {
                scheduledTimeText(scheduledPrimary)
                statusText(for: Self.timetableStatus)
            } else {
                loadingText
            }
            destinationLine
            savedArrivalsLine
        }
    }

    private var nameText: some View {
        HStack(spacing: 4) {
            if row.isPinned {
                BookmarkPinIndicator()
            }
            Text(row.name)
                .font(.stopRowTitle)
                .foregroundStyle(.primary)
                .lineLimit(isAccessibilitySize ? nil : 2)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if let primary {
            let status = DepartureStatus(arrivalDeparture: primary)
            let display = DepartureTimeDisplay(arrivalDeparture: primary, formatters: formatters)
            // The trailing countdown column narrows this one; when a corrected
            // time ("~~10:41 PM~~ 10:42 PM") and the status don't fit on one
            // line, the status moves below instead of the time wrapping mid-pair.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    timeText(display)
                    Text("·")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                    statusText(for: status)
                }
                .fixedSize()
                VStack(alignment: .leading, spacing: 1) {
                    timeText(display)
                    statusText(for: status)
                }
            }
        } else if let scheduledPrimary {
            HStack(spacing: 6) {
                scheduledTimeText(scheduledPrimary)
                Text("·")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                statusText(for: Self.timetableStatus)
            }
        } else {
            loadingText
        }
    }

    private func scheduledTimeText(_ departure: ScheduledDeparture) -> some View {
        Text(formatters.timeFormatter.string(from: departure.date))
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private func timeText(_ display: DepartureTimeDisplay) -> some View {
        // Shared corrected-time component (#1225): when a prediction moves the
        // trip off its timetable, the scheduled time renders struck through
        // ahead of the time the rider should act on. The spoken equivalent is
        // appended in `Formatters.accessibilityValue(for:)` — this card's label
        // uses `children: .ignore`, so the visual view can't carry it.
        DepartureTimeText(display: display)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private func statusText(for status: DepartureStatus) -> some View {
        Text(status.label)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color(uiColor: status.color))
    }

    /// Arrival at the bookmark's destination stop, below the departure it belongs
    /// to. Shown only for destination bookmarks with a departure to describe;
    /// the "no trip stops there" case replaces the status line instead (#1080).
    /// The glyph sits inline rather than in a `Label`'s icon column, which
    /// indented the text by a full icon width.
    @ViewBuilder
    private var destinationLine: some View {
        if primary != nil, let text = formatters.destinationText(for: row) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "arrow.turn.down.right")
                    .imageScale(.small)
                    // Points into the text, so it follows reading direction.
                    .flipsForRightToLeftLayoutDirection(true)
                Text(text)
                    .lineLimit(isAccessibilitySize ? nil : 2)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(destinationColor)
        }
    }

    private var destinationColor: Color {
        if case .arrives(let arrival) = row.destinationStatus, arrival.isRealTime {
            return .primary
        }
        return .secondary
    }

    /// "Offline, saved 8:42 AM" while the departures shown are saved ones,
    /// because the device couldn't reach the server.
    @ViewBuilder
    private var savedArrivalsLine: some View {
        if let text = formatters.savedArrivalsText(for: row) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "wifi.slash")
                    .imageScale(.small)
                Text(text)
                    .lineLimit(isAccessibilitySize ? nil : 2)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    /// Placeholder for the status line while there's no primary departure:
    /// "Loading..." until the stop's fetch completes, then an explicit
    /// no-departures message — a fetched-but-empty result must not look like
    /// it's loading forever.
    @ViewBuilder
    private var loadingText: some View {
        if row.destinationStatus == .notServed, let text = formatters.destinationText(for: row) {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if row.savedArrivalsDate == nil {
            // Offline with no saved departures left, `savedArrivalsLine` says
            // it all: "No upcoming departures" would claim more than it knows.
            noDeparturesText
        }
    }

    /// Shared with the home sheet's bookmark cards, so the two say the same thing.
    static func noDeparturesMessage(hasLoadedArrivalData: Bool) -> String {
        hasLoadedArrivalData
            ? OBALoc("bookmarks_controller.no_upcoming_departures", value: "No upcoming departures", comment: "Shown on a bookmark card when arrival data has loaded but there are no departures in the near future")
            : OBALoc("loading", value: "Loading...", comment: "Loading state text")
    }

    private var noDeparturesText: some View {
        Text(Self.noDeparturesMessage(hasLoadedArrivalData: row.hasLoadedArrivalData))
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private func countdownBadge(for departure: ArrivalDeparture) -> some View {
        let status = DepartureStatus(arrivalDeparture: departure)
        return CountdownView(
            minutes: departure.arrivalDepartureMinutes,
            // A saved prediction is no longer live, so it doesn't get the
            // real-time treatment.
            isRealTime: status.isRealTime && row.savedArrivalsDate == nil,
            color: Color(uiColor: status.color)
        )
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            flashColor(for: departure, base: .clear),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    // MARK: - Chips

    private var chipViews: some View {
        // departureTime is NOT a safe ForEach identity: two distinct trips can
        // legitimately share a departure time (see TripLiveActivityCardView).
        // `chips` is a small, ordered list that's fully replaced on every
        // rebuild, so positional identity is safe and can't collide.
        ForEach(Array(chips.enumerated()), id: \.offset) { _, departure in
            departurePill(for: departure)
        }
    }

    private var scheduledChipViews: some View {
        ForEach(Array(scheduledChips.enumerated()), id: \.offset) { _, departure in
            pill(minutes: max(0, departure.minutes), status: Self.timetableStatus, background: Color(uiColor: Self.timetableStatus.color).opacity(0.14))
        }
    }

    private func departurePill(for departure: ArrivalDeparture) -> some View {
        let status = DepartureStatus(arrivalDeparture: departure)
        let color = Color(uiColor: status.color)
        return pill(
            minutes: max(0, departure.arrivalDepartureMinutes),
            status: status,
            background: flashColor(for: departure, base: color.opacity(0.14))
        )
    }

    private func pill(minutes: Int, status: DepartureStatus, background: Color) -> some View {
        let color = Color(uiColor: status.color)
        return StatusGlyphLabel(
            text: minutes == 0
                ? OBALoc("stop_page.countdown.now", value: "NOW", comment: "Shown in place of the minutes countdown when the vehicle is departing now")
                : Formatters.shortMinutesText(minutes),
            status: status
        )
            .font(.caption.weight(.heavy))
            .monospacedDigit()
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background, in: RoundedRectangle(cornerRadius: 8))
    }

    /// A timetable departure's countdown: never real-time, and never flashes,
    /// since nothing about it changes between refreshes.
    private func scheduledCountdown(for departure: ScheduledDeparture) -> some View {
        CountdownView(
            minutes: max(0, departure.minutes),
            isRealTime: false,
            color: Color(uiColor: Self.timetableStatus.color)
        )
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }

    // MARK: - Highlight Flash

    /// Badge background while a changed departure time is flashing; `base`
    /// otherwise. Mirrors the legacy bookmark cell's highlight mechanic.
    private func flashColor(for departure: ArrivalDeparture, base: Color) -> Color {
        if flashing && flashedTripIDs.contains(departure.tripID) {
            return Color(uiColor: ThemeColors.shared.propertyChanged)
        }
        return base
    }

    private func flashIfNeeded() {
        guard !row.highlightedTripIDs.isEmpty else { return }

        flashedTripIDs = row.highlightedTripIDs
        flashDismissal?.cancel()
        withAnimation(.easeInOut(duration: 0.3)) {
            flashing = true
        }
        flashDismissal = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.5)) {
                flashing = false
            }
        }
    }
}

// MARK: - StopBookmarkRow

/// Row for a whole-stop bookmark: name + stop glyph + served-routes subtitle.
/// No countdown or adherence line — a stop bookmark has no single trip to
/// track, so the row doesn't pretend to be loading one.
struct StopBookmarkRow: View {
    let row: BookmarkRowViewModel

    @Environment(\.obaFormatters) private var formatters
    @ScaledMetric(relativeTo: .body) private var badgeScale: CGFloat = 1

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Same rounded-square silhouette as RouteBadgeView so trip cards
            // and stop rows share one visual anchor; brand color marks it as
            // identity-less (no route).
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 19 * badgeScale, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44 * badgeScale, height: 44 * badgeScale)
                .background(
                    Color(uiColor: ThemeColors.shared.brand).gradient,
                    in: RoundedRectangle(cornerRadius: 44 * badgeScale * 0.28, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if row.isPinned {
                        BookmarkPinIndicator()
                    }
                    Text(row.name)
                        .font(.stopRowTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                if let subtitle = row.routesSubtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel(base: formatters.accessibilityLabel(for: row)))
        .accessibilityIdentifier("bookmark_row")
        .accessibilityAddTraits(.isButton)
    }
}
