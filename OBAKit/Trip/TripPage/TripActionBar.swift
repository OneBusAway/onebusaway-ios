//
//  TripActionBar.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The pinned actions at the foot of the trip page.
///
/// Pinned rather than scrolled with the content: on a sixty-stop trip these
/// would otherwise be a long scroll away, and tracking a bus is the thing a
/// rider most often opens this page to do.
struct TripActionBar: View {
    /// Live Activities need a real-time trip to report on, and the platform has
    /// to allow them. Hidden rather than disabled when unavailable — a dead
    /// primary button is worse than no primary button.
    let canStartLiveActivity: Bool
    let isTrackingLiveActivity: Bool
    let canSchedule: Bool
    let canAlarm: Bool
    let hasAlarm: Bool
    let onLiveActivity: () -> Void
    let onBookmark: () -> Void
    let onSchedule: () -> Void
    let onAlarm: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 10) {
            if canStartLiveActivity {
                liveActivityButton
            }
            secondaryActions
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
    }

    private var liveActivityButton: some View {
        Button(action: onLiveActivity) {
            Label {
                Text(isTrackingLiveActivity
                     ? OBALoc("trip_page.live_activity_tracking", value: "Tracking on Lock Screen", comment: "Trip page button state once a Live Activity is running for this trip.")
                     : OBALoc("trip_page.live_activity_start", value: "Live Activity — track on Lock Screen", comment: "Trip page button that starts a Live Activity for this trip."))
                .font(.body.weight(.semibold))
            } icon: {
                Image(systemName: "waveform.path.ecg")
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color(uiColor: ThemeColors.shared.departureOnTime))
        .foregroundStyle(.white)
        .disabled(isTrackingLiveActivity)
    }

    /// Side by side at normal sizes; stacked once the labels need the width, so
    /// each stays a full-width target rather than truncating to an icon.
    private var secondaryActions: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))

        return layout {
            secondaryButton(title: Strings.addBookmark, systemImage: "bookmark", action: onBookmark)

            if canSchedule {
                secondaryButton(
                    title: OBALoc("trip_page.view_schedule", value: "View schedule", comment: "Trip page button opening the route's schedule."),
                    systemImage: "calendar",
                    action: onSchedule
                )
            }

            if canAlarm {
                secondaryButton(
                    title: hasAlarm
                        ? OBALoc("trip_page.remove_alarm", value: "Remove alarm", comment: "Trip page button cancelling this trip's arrival alarm.")
                        : Strings.addAlarm,
                    systemImage: hasAlarm ? "bell.fill" : "bell",
                    action: onAlarm
                )
            }
        }
    }

    private func secondaryButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(Color(uiColor: .label))
    }
}
