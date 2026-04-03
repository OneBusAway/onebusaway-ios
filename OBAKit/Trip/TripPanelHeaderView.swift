//
//  TripPanelHeaderView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

// MARK: - TripPanelHeaderView

/// Modern Apple Maps-style bottom-sheet header.
///
/// Layout:
/// ```
/// ┌──────────────────────────────────────────────────┐
/// │  SIM4C - MIDTOWN via CHURCH ST …   ● Live   26m  │
/// │  9:46 PM · Scheduled/not real-time               │
/// │  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  12 stops left │  ← progress + chip
/// ├──────────────────────────────────────────────────┤
/// │  WOODROW RD/VINELAND AV                       >  │  ← next stop callout
/// │  9:45 PM                          +3 min late    │  ← delay badge
/// └──────────────────────────────────────────────────┘
/// ```
struct TripPanelHeaderView: View {
    let routeHeadsign: String
    let scheduledTime: String
    let statusText: String
    let minutesUntilArrival: Int?
    let isRealTime: Bool
    var nextStopName: String? = nil
    var nextStopTime: String? = nil
    /// 0.0–1.0 fraction of stops already passed. `nil` hides the progress bar.
    var routeProgress: Double? = nil
    /// Number of stops remaining after the current vehicle position.
    var stopsRemaining: Int? = nil
    /// Positive = late, negative = early, nil = on-time / unknown.
    var scheduleDeviationMinutes: Int? = nil
    var onTapNextStop: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Title row ────────────────────────────────────────────────
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(routeHeadsign)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(3)

                    if !scheduledTime.isEmpty || !statusText.isEmpty {
                        HStack(spacing: 0) {
                            if !scheduledTime.isEmpty { Text(scheduledTime).monospacedDigit() }
                            if !scheduledTime.isEmpty && !statusText.isEmpty { Text(" · ") }
                            if !statusText.isEmpty { Text(statusText) }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 4) {
                    if isRealTime { LiveIndicatorPill() }
                    if let minutes = minutesUntilArrival {
                        MinutesBadgeView(minutes: minutes, isRealTime: isRealTime)
                    }
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, routeProgress != nil ? 8 : 14)

            // ── Progress bar + stops-remaining chip ──────────────────────
            if let progress = routeProgress {
                HStack(alignment: .center, spacing: 10) {
                    RouteProgressBar(progress: progress)

                    if let remaining = stopsRemaining, remaining > 0 {
                        Text("\(remaining) stop\(remaining == 1 ? "" : "s") left")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }

            // ── Next stop callout ────────────────────────────────────────
            // No extra Divider here — the callout is visually part of the header block,
            // separated only by the outer Divider in TripStopListView.
            if let stopName = nextStopName {
                Divider()
                    .padding(.horizontal, 16)

                Button { onTapNextStop?() } label: {
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stopName)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if let time = nextStopTime {
                                HStack(spacing: 6) {
                                    Text(time)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                    if let dev = scheduleDeviationMinutes, dev != 0 {
                                        DelayBadge(minutes: dev)
                                    }
                                }
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(nextStopA11yLabel)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(headerA11yLabel)
    }

    private var headerA11yLabel: String {
        var parts = [routeHeadsign]
        if !scheduledTime.isEmpty { parts.append(scheduledTime) }
        if !statusText.isEmpty    { parts.append(statusText) }
        if let m = minutesUntilArrival { parts.append("\(m) minutes") }
        if isRealTime { parts.append("Real-time tracking") }
        if let r = stopsRemaining { parts.append("\(r) stops remaining") }
        return parts.joined(separator: ", ")
    }

    private var nextStopA11yLabel: String {
        var parts: [String] = []
        if let name = nextStopName { parts.append("Next stop: \(name)") }
        if let time = nextStopTime { parts.append(time) }
        if let dev = scheduleDeviationMinutes, dev != 0 {
            parts.append(dev > 0 ? "\(dev) minutes late" : "\(abs(dev)) minutes early")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - DelayBadge

/// Compact pill showing schedule deviation — red for late, green for early.
struct DelayBadge: View {
    let minutes: Int

    private var isLate: Bool { minutes > 0 }
    private var color: Color { isLate ? .red : Color(.systemGreen) }
    private var label: String {
        isLate ? "+\(minutes) min late" : "\(abs(minutes)) min early"
    }

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .accessibilityLabel(isLate ? "\(minutes) minutes late" : "\(abs(minutes)) minutes early")
    }
}

// MARK: - LiveIndicatorPill

struct LiveIndicatorPill: View {
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(.systemGreen))
                .frame(width: 7, height: 7)
                .scaleEffect(pulsing ? 1.3 : 1.0)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulsing)
                .onAppear { pulsing = true }
            Text("Live")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(.systemGreen))
        }
        .accessibilityLabel("Real-time tracking active")
    }
}

// MARK: - RouteProgressBar

struct RouteProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.systemFill)).frame(height: 4)
                Capsule()
                    .fill(Color(.systemGreen))
                    .frame(width: max(8, geo.size.width * progress), height: 4)
                    .animation(.easeInOut(duration: 0.4), value: progress)
            }
        }
        .frame(height: 4)
        .accessibilityLabel("Route progress: \(Int(progress * 100)) percent")
    }
}

// MARK: - MinutesBadgeView

struct MinutesBadgeView: View {
    let minutes: Int
    let isRealTime: Bool

    private var color: Color {
        switch minutes {
        case ..<2:  return .red
        case 2..<5: return .orange
        default:    return isRealTime ? Color(.systemGreen) : .orange
        }
    }

    var body: some View {
        Text("\(minutes)m")
            .font(.system(size: 26, weight: .bold))
            .foregroundStyle(color)
            .monospacedDigit()
            .accessibilityLabel("\(minutes) minutes")
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Scheduled — late") {
    TripPanelHeaderView(
        routeHeadsign: "SIM4C - MIDTOWN via CHURCH ST via MADISON AV",
        scheduledTime: "9:46 PM",
        statusText: "Scheduled/not real-time",
        minutesUntilArrival: 26,
        isRealTime: false,
        nextStopName: "WOODROW RD/VINELAND AV",
        nextStopTime: "9:45 PM",
        routeProgress: 0.18,
        stopsRemaining: 14,
        scheduleDeviationMinutes: 3
    )
    .background(Color(.systemBackground))
    .preferredColorScheme(.dark)
}

#Preview("Real-time — on time") {
    TripPanelHeaderView(
        routeHeadsign: "SIM7 - GREENWICH VILLAGE via WEST ST",
        scheduledTime: "6:57 PM",
        statusText: "On time",
        minutesUntilArrival: 8,
        isRealTime: true,
        nextStopName: "RICHMOND AV/KATAN AV",
        nextStopTime: "6:58 PM",
        routeProgress: 0.55,
        stopsRemaining: 6,
        scheduleDeviationMinutes: 0
    )
    .background(Color(.systemBackground))
    .preferredColorScheme(.dark)
}

#Preview("Real-time — early") {
    TripPanelHeaderView(
        routeHeadsign: "44 - Ballard via Fremont",
        scheduledTime: "6:57 PM",
        statusText: "2 min early",
        minutesUntilArrival: 4,
        isRealTime: true,
        nextStopName: "ARDEN AV/HAMPTON GREEN",
        nextStopTime: "6:55 PM",
        routeProgress: 0.72,
        stopsRemaining: 3,
        scheduleDeviationMinutes: -2
    )
    .background(Color(.systemBackground))
    .preferredColorScheme(.dark)
}
#endif
