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
/// route badge + headsign + scheduled time/adherence status + countdown + departure chips.
/// No alarm pill or expand chevron.
public struct TripLiveActivityCardView: View {
    public let staticData: TripAttributes.StaticData
    public let contentState: TripAttributes.ContentState

    private let presenter = TripActivityPresenter()

    public init(staticData: TripAttributes.StaticData, contentState: TripAttributes.ContentState) {
        self.staticData = staticData
        self.contentState = contentState
    }

    public var body: some View {
        let now = Date()
        let upcoming = contentState.upcomingArrivals(now: now)
        let primary = upcoming.first
        let chips = Array(upcoming.dropFirst())

        VStack(alignment: .leading, spacing: 10) {
            primaryRow(primary: primary, now: now)
            if !chips.isEmpty {
                chipsRow(chips: chips, now: now)
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
        HStack(spacing: 6) {
            Text(arrival.departureDate, style: .time)
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text("·")
                .font(.footnote)
                .foregroundStyle(.tertiary)
            Text(presenter.deviationLabel(for: arrival, now: now))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color(uiColor: presenter.color(for: arrival)))
        }
    }

    @ViewBuilder
    private func countdownBadge(for arrival: TripAttributes.ContentState.ArrivalInfo, now: Date) -> some View {
        CountdownView(
            minutes: Int(arrival.departureDate.timeIntervalSince(now) / 60.0),
            isRealTime: arrival.scheduleStatus != .unknown,
            color: Color(uiColor: presenter.color(for: arrival))
        )
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
        let minutes = max(0, Int(arrival.departureDate.timeIntervalSince(now) / 60.0))
        Text(minutes == 0
             ? OBALoc("stop_page.countdown.now", value: "NOW", comment: "Shown in place of the minutes countdown when the vehicle is departing now")
             : "\(minutes)m")
            .font(.caption.weight(.heavy))
            .monospacedDigit()
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
