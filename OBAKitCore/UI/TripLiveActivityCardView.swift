//
//  TripLiveActivityCardView.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

/// Lock-screen Live Activity card that matches the grouped route card header from StopPageView:
/// route badge + headsign + corrected departure time (the scheduled time struck through when a
/// prediction has moved it) with adherence status + countdown + departure chips.
/// No alarm pill or expand chevron.
public struct TripLiveActivityCardView: View {
    public let staticData: TripAttributes.StaticData
    public let contentState: TripAttributes.ContentState
    /// From `ActivityViewContext.isStale` — ActivityKit flips this after `staleDate`.
    public let isStale: Bool

    private let presenter = TripActivityPresenter()

    public init(
        staticData: TripAttributes.StaticData,
        contentState: TripAttributes.ContentState,
        isStale: Bool = false
    ) {
        self.staticData = staticData
        self.contentState = contentState
        self.isStale = isStale
    }

    public var body: some View {
        let now = Date()
        let upcoming = contentState.upcomingArrivals(now: now)
        let primary = upcoming.first
        let chips = Array(upcoming.dropFirst())

        VStack(alignment: .leading, spacing: 10) {
            // Dim arrival content only — the stale warning must stay full
            // opacity or light-mode orange ~1.6:1 and becomes unreadable (#1376).
            VStack(alignment: .leading, spacing: 10) {
                primaryRow(primary: primary, now: now)
                if !chips.isEmpty {
                    chipsRow(chips: chips, now: now)
                }
            }
            .opacity(LiveActivityStaleChrome.contentOpacity(isStale: isStale))

            if isStale {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(LiveActivityStaleChrome.warningText)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(uiColor: .systemBackground))
    }

    @ViewBuilder
    private func primaryRow(primary: TripAttributes.ContentState.ArrivalInfo?, now: Date) -> some View {
        HStack(alignment: .center, spacing: 13) {
            RouteBadgeView(
                routeShortName: staticData.routeShortName,
                routeColor: resolvedRouteColor,
                size: 48
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(staticData.routeHeadsign)
                    .font(.headline.weight(.heavy))
                    .lineLimit(2)
                if let primary {
                    timeStatusLine(for: primary, now: now)
                }
            }
            Spacer(minLength: 8)
            if let primary {
                countdownBadge(for: primary, now: now)
            }
        }
    }

    @ViewBuilder
    private func timeStatusLine(for arrival: TripAttributes.ContentState.ArrivalInfo, now: Date) -> some View {
        // Shared corrected-time component (#1225): when the prediction has
        // moved off the timetable, the scheduled time renders struck through
        // ahead of the corrected one.
        let display = presenter.timeDisplay(for: arrival)
        let deviation = presenter.deviationLabel(for: arrival, now: now)

        HStack(spacing: 6) {
            DepartureTimeText(display: display)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("·")
                .font(.footnote)
                .foregroundStyle(.tertiary)
            Text(deviation)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color(uiColor: presenter.color(for: arrival)))
        }
        // `DepartureTimeText` hides itself from VoiceOver (a strikethrough is
        // inaudible), so the line speaks the combined clause instead.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(display.accessibilityTimeDescription), \(deviation)")
    }

    @ViewBuilder
    private func countdownBadge(for arrival: TripAttributes.ContentState.ArrivalInfo, now: Date) -> some View {
        let color = Color(uiColor: presenter.color(for: arrival))
        let isRealTime = arrival.scheduleStatus != .unknown
        VStack(spacing: 1) {
            HStack(alignment: .top, spacing: 2) {
                // Use SwiftUI's date-relative Text so the countdown ticks
                // automatically on the lock screen without requiring a push
                // to re-render the snapshot. (#1187)
                //
                // The `if` is evaluated once when the snapshot is rendered —
                // Live Activity `body` is NOT re-invoked between pushes, so
                // there is no risk of the surrounding condition flipping while
                // Text(.relative) is ticking. `upcomingArrivals` dropping an
                // arrival only happens on the next push, at which point a fresh
                // snapshot replaces this one entirely. The `else` branch handles
                // snapshots rendered at or after the departure time (e.g. a
                // late-arriving push), showing "NOW" rather than a negative
                // "X seconds ago" string.
                if arrival.departureDate > now {
                    Text(arrival.departureDate, style: .relative)
                        .font(.system(.title2, design: .rounded, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(color)
                        // Suppress the default "in X minutes" VoiceOver phrasing;
                        // the parent row speaks its own combined a11y label.
                        .accessibilityHidden(true)
                } else {
                    Text(OBALoc("stop_page.countdown.now", value: "NOW",
                                comment: "Shown in place of the minutes countdown when the vehicle is departing now"))
                        .font(.system(.title2, design: .rounded, weight: .heavy))
                        .foregroundStyle(color)
                        .accessibilityHidden(true)
                }
                RealtimeGlyph(isRealTime: isRealTime, color: color, size: 11)
                    .padding(.top, 1)
            }
        }
    }

    @ViewBuilder
    private func chipsRow(chips: [TripAttributes.ContentState.ArrivalInfo], now: Date) -> some View {
        HStack(spacing: 8) {
            // departureTime is NOT a safe identity here: the server can (and,
            // due to an upstream OBA bug, briefly did) emit duplicate
            // departure times, and even with that fixed server-side, two
            // genuinely distinct trips can legitimately share a departure
            // time. Duplicate ForEach IDs are undefined behavior in SwiftUI.
            // `chips` is a small, ordered, server-supplied list that's fully
            // replaced on every content update, so positional identity is
            // safe and can't collide.
            ForEach(Array(chips.enumerated()), id: \.offset) { _, arrival in
                departurePill(for: arrival, now: now)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func departurePill(for arrival: TripAttributes.ContentState.ArrivalInfo, now: Date) -> some View {
        let color = Color(uiColor: presenter.color(for: arrival))
        // Use date-relative Text so the chip ticks automatically on the lock
        // screen without a keepalive push. (#1187)
        // `body` is not re-invoked between pushes in a Live Activity — the
        // `if` is evaluated once at snapshot render time. See countdownBadge
        // for a full explanation of the rendering model.
        Group {
            if arrival.departureDate > now {
                Text(arrival.departureDate, style: .relative)
                    .monospacedDigit()
            } else {
                Text(OBALoc("stop_page.countdown.now", value: "NOW",
                            comment: "Shown in place of the minutes countdown when the vehicle is departing now"))
            }
        }
        .font(.caption.weight(.heavy))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
    }

    private var resolvedRouteColor: Color {
        guard let hex = staticData.routeColorHex else { return Color(uiColor: ThemeColors.shared.brand) }
        return Color(uiColor: UIColor(hex: hex) ?? ThemeColors.shared.brand)
    }
}
