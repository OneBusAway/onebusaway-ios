//
//  TripLiveActivity.swift
//  OBAWidget
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//
/*
 
        _________________________________________________________
      /                                                           \
     |   [BUS]        C Line                                5m     |  <-- Header
     |                                                             |      (Route & Primary Time)
     |   ───────────────────────────────────────────────────────   |  <-- Horizontal Divider
     |                                                             |
     |   West Seattle Alaska                               11m     |  <-- Details
     |   Junction                                          15m     |      (Left: Destination)
     |   • On Time                                                 |      (Right: Stacked Times)
      \___________________________________________________________/
 */

import ActivityKit
import WidgetKit
import SwiftUI
import OBAKitCore

struct TripLiveActivity: Widget {
    private let presenter = TripActivityPresenter()

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripAttributes.self) { context in
            TripLiveActivityContentView(context: context)
                .widgetURL(
                    URLSchemeRouter(scheme: Bundle.main.extensionURLScheme!)
                        .encodeViewStop(stopID: context.attributes.staticData.stopID, regionID: context.attributes.staticData.regionID)
                )
        } dynamicIsland: { context in
            let upcoming = context.state.upcomingArrivals()
            let primary = upcoming.first
            let staleOpacity = LiveActivityStaleChrome.contentOpacity(isStale: context.isStale)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        if context.isStale {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.orange)
                                .accessibilityLabel(LiveActivityStaleChrome.warningText)
                        } else {
                            Image(systemName: "bus.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color(presenter.primaryColor(for: context.state)))
                                .accessibilityHidden(true) // decorative; the route name follows
                        }
                        Text(context.attributes.staticData.routeShortName)
                            .font(.system(.title3, design: .rounded))
                            .fontWeight(.heavy)
                            .foregroundColor(.white)
                            .opacity(staleOpacity)
                            .accessibilityLabel(routeLabel(context.attributes.staticData))
                    }
                    .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let primary {
                        TickingCountdownText(
                            departure: primary.departureDate,
                            font: .system(size: 32, weight: .bold, design: .rounded),
                            color: Color(presenter.color(for: primary)),
                            opacity: staleOpacity
                        )
                        .padding(.trailing, 6)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.white.opacity(0.15))
                            .frame(height: 1)
                            .padding(.vertical, 8)
                        // Dim headsign/minutes only; warning stays full opacity (#1376).
                        HStack(alignment: .top, spacing: 0) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(context.attributes.staticData.routeHeadsign)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.85)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color(presenter.primaryColor(for: context.state)))
                                        .frame(width: 6, height: 6)
                                    Text(primary.map { presenter.statusText(for: $0) } ?? "")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(Color(presenter.primaryColor(for: context.state)))
                                }
                                .padding(.top, 2)
                            }
                            .padding(.leading, 6)
                            Spacer(minLength: 12)
                            VStack(alignment: .trailing, spacing: 4) {
                                let nextDepartures = upcoming.dropFirst().prefix(2)
                                ForEach(Array(nextDepartures.enumerated()), id: \.offset) { _, arrivalInfo in
                                    TickingCountdownText(
                                        departure: arrivalInfo.departureDate,
                                        font: .system(.callout, design: .rounded, weight: .bold),
                                        color: Color(presenter.color(for: arrivalInfo))
                                    )
                                }
                            }
                            .padding(.trailing, 6)
                        }
                        .opacity(staleOpacity)

                        if context.isStale {
                            Text(LiveActivityStaleChrome.warningText)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 6)
                                .padding(.top, 4)
                        }
                    }
                }
            } compactLeading: {
                // MARK: - COMPACT LEADING
                Group {
                    if context.isStale {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                            .accessibilityLabel(LiveActivityStaleChrome.warningText)
                    } else {
                        Text(context.attributes.staticData.routeShortName)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundColor(Color(presenter.primaryColor(for: context.state)))
                            .accessibilityLabel(routeLabel(context.attributes.staticData))
                    }
                }
                .padding(.leading, 4)
            } compactTrailing: {
                if let primary {
                    TickingCountdownText(
                        departure: primary.departureDate,
                        font: .system(.body, design: .rounded, weight: .bold),
                        color: Color(presenter.color(for: primary)),
                        opacity: staleOpacity
                    )
                    .frame(minWidth: 20)
                }
            } minimal: {
                // Keep the countdown when stale — minimal has no room for both
                // a warning glyph and minutes, and minutes are the only ETA the
                // rider gets here. Compact and minimal are mutually exclusive
                // presentations, so there is no compact leading triangle to lean on.
                if let primary {
                    let minuteText = TickingCountdownText.spokenSnapshot(departure: primary.departureDate, now: Date())
                    TickingCountdownText(
                        departure: primary.departureDate,
                        font: .system(.callout, design: .rounded, weight: .heavy),
                        color: context.isStale
                            ? .orange
                            : Color(presenter.color(for: primary)),
                        opacity: staleOpacity,
                        accessibilityLabel: context.isStale
                            ? "\(LiveActivityStaleChrome.warningText), \(minuteText)"
                            : nil
                    )
                }
            }
        }
        // Without `.small`, the Watch Smart Stack and CarPlay fall back to the
        // compact Island pair: a bare route and minutes.
        .supplementalActivityFamilies([.small])
    }
}

/// "Route 8" rather than a bare "8", which VoiceOver reads as a number with
/// nothing to say what it counts.
private func routeLabel(_ staticData: TripAttributes.StaticData) -> String {
    Formatters(locale: .autoupdatingCurrent, calendar: .autoupdatingCurrent, themeColors: ThemeColors.shared)
        .accessibilityLabelForArrivalDeparture(routeAndHeadsign: staticData.routeShortName)
}

/// The Lock Screen card on iPhone; a smaller layout in the Watch Smart Stack
/// and CarPlay, which ask for `.small`.
private struct TripLiveActivityContentView: View {
    let context: ActivityViewContext<TripAttributes>

    @Environment(\.activityFamily) private var activityFamily

    var body: some View {
        switch activityFamily {
        case .small:
            // The phone resolves colors in its own appearance, so a light-mode
            // phone tinted the Smart Stack card white while the watch drew the
            // text for its dark face: illegible once the wrist was raised.
            TripLiveActivitySmallView(context: context)
                .environment(\.colorScheme, .dark)
                .activityBackgroundTint(.black)
        default:
            TripLiveActivityCardView(
                staticData: context.attributes.staticData,
                contentState: context.state,
                isStale: context.isStale,
                showsDismissHint: context.attributes.showsDismissHint
            )
            .activityBackgroundTint(Color(UIColor.systemBackground))
        }
    }
}

/// Route and minutes on the first line, then the headsign and how the bus is
/// running — what the rider glances at on their wrist.
private struct TripLiveActivitySmallView: View {
    let context: ActivityViewContext<TripAttributes>

    private let presenter = TripActivityPresenter()

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        let staticData = context.attributes.staticData
        let now = Date()
        let primary = context.state.upcomingArrivals(now: now).first

        VStack(alignment: .leading, spacing: 2) {
            // Dim arrival content only; the warning stays full opacity (#1376).
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(staticData.routeShortName)
                        .font(.system(.headline, design: .rounded, weight: .heavy))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let primary {
                        CountdownView(
                            departure: primary.departureDate,
                            isRealTime: primary.scheduleStatus != .unknown,
                            color: Color(presenter.color(for: primary)),
                            isLiveActivity: true
                        )
                    }
                }
                Text(staticData.routeHeadsign)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .opacity(LiveActivityStaleChrome.contentOpacity(isStale: context.isStale))

            if context.isStale {
                Label(LiveActivityStaleChrome.warningText, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LiveActivityStaleChrome.warningColor)
                    .lineLimit(1)
            } else if let primary {
                Text(presenter.statusText(for: primary, now: now))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(presenter.color(for: primary)))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // The Lock Screen card's label, so every surface speaks the same words.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TripLiveActivityCardView.accessibilityLabel(
            staticData: staticData,
            contentState: context.state,
            isStale: context.isStale,
            isLuminanceReduced: isLuminanceReduced,
            now: now,
            presenter: presenter
        ))
        .accessibilityAddTraits(.updatesFrequently)
    }
}
