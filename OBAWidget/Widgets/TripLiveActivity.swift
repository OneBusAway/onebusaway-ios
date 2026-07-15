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
            TripLiveActivityCardView(
                staticData: context.attributes.staticData,
                contentState: context.state
            )
            .activityBackgroundTint(Color(UIColor.systemBackground))
            .widgetURL(
                URLSchemeRouter(scheme: Bundle.main.extensionURLScheme!)
                    .encodeViewStop(stopID: context.attributes.staticData.stopID, regionID: context.attributes.staticData.regionID)
            )
        } dynamicIsland: { context in
            let upcoming = context.state.upcomingArrivals()
            let primary = upcoming.first
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        Image(systemName: "bus.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(presenter.primaryColor(for: context.state)))
                        Text(context.attributes.staticData.routeShortName)
                            .font(.system(.title3, design: .rounded))
                            .fontWeight(.heavy)
                            .foregroundColor(.white)
                    }
                    .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let primary {
                        let primaryMinuteText = presenter.minuteText(for: primary)
                        Text(primaryMinuteText)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(Color(presenter.color(for: primary)))
                            .contentTransition(.numericText(value: Double(primaryMinuteText.filter("0123456789".contains)) ?? 0))
                            .padding(.trailing, 6)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.white.opacity(0.15))
                            .frame(height: 1)
                            .padding(.vertical, 8)
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
                                    Text(presenter.minuteText(for: arrivalInfo))
                                        .font(.system(.callout, design: .rounded))
                                        .fontWeight(.bold)
                                        .foregroundColor(Color(presenter.color(for: arrivalInfo)))
                                }
                            }
                            .padding(.trailing, 6)
                        }
                    }
                }
            } compactLeading: {
                // MARK: - COMPACT LEADING
                Text(context.attributes.staticData.routeShortName)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(Color(presenter.primaryColor(for: context.state)))
                    .padding(.leading, 4)
            } compactTrailing: {
                if let primary {
                    Text(presenter.minuteText(for: primary))
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(Color(presenter.color(for: primary)))
                        .frame(minWidth: 20)
                }
            } minimal: {
                if let primary {
                    Text(presenter.minuteText(for: primary))
                        .font(.system(.callout, design: .rounded))
                        .fontWeight(.heavy)
                        .foregroundColor(Color(presenter.color(for: primary)))
                }
            }
        }
    }
}
