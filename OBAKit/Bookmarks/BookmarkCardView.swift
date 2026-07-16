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

/// Trip-bookmark card matching the Live Activity lock-screen card
/// (`TripLiveActivityCardView`) and the Stop page's grouped route card header:
/// route badge + bookmark name + "time · adherence" line + countdown +
/// upcoming-departure chips.
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

    private var primary: ArrivalDeparture? { row.arrivalDepartures.first }
    private var chips: [ArrivalDeparture] { Array(row.arrivalDepartures.dropFirst().prefix(2)) }

    private var routeColor: Color {
        Color(uiColor: primary?.route.color ?? ThemeColors.shared.brand)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isAccessibilitySize {
                accessibilityPrimaryRow
            } else {
                primaryRow
            }
            if !chips.isEmpty {
                chipsRow
            }
        }
        .onAppear { flashIfNeeded() }
        .onChange(of: row.highlightedTripIDs) { flashIfNeeded() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(formatters.accessibilityLabel(for: row))
        .accessibilityValue(formatters.accessibilityValue(for: row) ?? "")
        .accessibilityAddTraits([.isButton, .updatesFrequently])
    }

    // MARK: - Primary Row

    private var primaryRow: some View {
        HStack(alignment: .center, spacing: 13) {
            RouteBadgeView(
                routeShortName: row.routeShortName ?? row.name,
                routeColor: routeColor,
                size: 48
            )
            VStack(alignment: .leading, spacing: 3) {
                nameText
                statusLine
            }
            Spacer(minLength: 8)
            if let primary {
                countdownBadge(for: primary)
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
                    routeColor: routeColor,
                    size: 48
                )
                Spacer(minLength: 8)
                if let primary {
                    countdownBadge(for: primary)
                }
            }
            nameText
            if let primary {
                timeText(for: primary)
                statusText(for: DepartureStatus(arrivalDeparture: primary))
            } else {
                loadingText
            }
        }
    }

    private var nameText: some View {
        Text(row.name)
            .font(.headline.weight(.heavy))
            .foregroundStyle(.primary)
            .lineLimit(isAccessibilitySize ? nil : 2)
    }

    @ViewBuilder
    private var statusLine: some View {
        if let primary {
            HStack(spacing: 6) {
                timeText(for: primary)
                Text("·")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                statusText(for: DepartureStatus(arrivalDeparture: primary))
            }
        } else {
            loadingText
        }
    }

    private func timeText(for departure: ArrivalDeparture) -> some View {
        Text(formatters.timeFormatter.string(from: departure.arrivalDepartureDate))
            .font(.footnote)
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }

    private func statusText(for status: DepartureStatus) -> some View {
        Text(status.label)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color(uiColor: status.color))
    }

    /// Placeholder for the status line while there's no primary departure:
    /// "Loading..." until the stop's fetch completes, then an explicit
    /// no-departures message — a fetched-but-empty result must not look like
    /// it's loading forever.
    private var loadingText: some View {
        Text(row.hasLoadedArrivalData
            ? OBALoc("bookmarks_controller.no_upcoming_departures", value: "No upcoming departures", comment: "Shown on a bookmark card when arrival data has loaded but there are no departures in the near future")
            : OBALoc("loading", value: "Loading...", comment: "Loading state text"))
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private func countdownBadge(for departure: ArrivalDeparture) -> some View {
        let status = DepartureStatus(arrivalDeparture: departure)
        return CountdownView(
            minutes: departure.arrivalDepartureMinutes,
            isRealTime: status.isRealTime,
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

    @ViewBuilder
    private var chipsRow: some View {
        if isAccessibilitySize {
            FlowLayout(hSpacing: 8, vSpacing: 8) {
                chipViews
            }
        } else {
            HStack(spacing: 8) {
                chipViews
                Spacer()
            }
        }
    }

    private var chipViews: some View {
        // departureTime is NOT a safe ForEach identity: two distinct trips can
        // legitimately share a departure time (see TripLiveActivityCardView).
        // `chips` is a small, ordered list that's fully replaced on every
        // rebuild, so positional identity is safe and can't collide.
        ForEach(Array(chips.enumerated()), id: \.offset) { _, departure in
            departurePill(for: departure)
        }
    }

    private func departurePill(for departure: ArrivalDeparture) -> some View {
        let status = DepartureStatus(arrivalDeparture: departure)
        let color = Color(uiColor: status.color)
        let minutes = max(0, departure.arrivalDepartureMinutes)
        return Text(minutes == 0
             ? OBALoc("stop_page.countdown.now", value: "NOW", comment: "Shown in place of the minutes countdown when the vehicle is departing now")
             : "\(minutes)m")
            .font(.caption.weight(.heavy))
            .monospacedDigit()
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                flashColor(for: departure, base: color.opacity(0.14)),
                in: RoundedRectangle(cornerRadius: 8)
            )
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
        HStack(alignment: .center, spacing: 13) {
            // Same rounded-square silhouette as RouteBadgeView so trip cards
            // and stop rows share one visual anchor; brand color marks it as
            // identity-less (no route).
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 20 * badgeScale, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48 * badgeScale, height: 48 * badgeScale)
                .background(
                    Color(uiColor: ThemeColors.shared.brand).gradient,
                    in: RoundedRectangle(cornerRadius: 48 * badgeScale * 0.28, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
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
        .accessibilityLabel(formatters.accessibilityLabel(for: row))
        .accessibilityAddTraits(.isButton)
    }
}
