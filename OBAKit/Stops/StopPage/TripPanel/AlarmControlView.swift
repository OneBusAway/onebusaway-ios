//
//  AlarmControlView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The trip panel's alarm block: a single "Set an alarm" button by default;
/// once set, an info row with Change and Cancel. Change re-presents the same
/// alarm-time-picker bulletin used to create the alarm.
///
/// Text uses Dynamic Type text styles; the fixed bell-circle dimension scales
/// with Dynamic Type via `@ScaledMetric`.
struct AlarmControlView: View {
    let alarmIsSet: Bool
    let leadTimeMinutes: Int
    let onSet: () -> Void
    let onCancel: () -> Void
    let onChange: () -> Void

    /// The bell circle grows with Dynamic Type the way the grouped alarm badge
    /// does: fixed dimensions scale with Dynamic Type via `@ScaledMetric`.
    @ScaledMetric(relativeTo: .body) private var bellCircleSize: CGFloat = 32

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var onTimeColor: Color { Color(uiColor: ThemeColors.shared.departureOnTime) }

    /// At accessibility sizes the alarm block stacks (the guide's committed
    /// layout): Change/Cancel drop below the label instead of competing with
    /// it for one line's width.
    private var isAccessibilitySize: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        VStack(spacing: 0) {
            if !alarmIsSet {
                Button(action: onSet) {
                    Label(OBALoc("stop_page.alarm.set", value: "Set an alarm", comment: "Primary alarm button in the trip panel"), systemImage: "bell")
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(uiColor: ThemeColors.shared.brand))
                .foregroundStyle(.white)
                .font(.body.weight(.semibold))
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "bell.fill")
                        .foregroundStyle(onTimeColor)
                        .frame(width: bellCircleSize, height: bellCircleSize)
                        .background(onTimeColor.opacity(0.14), in: Circle())
                        .accessibilityHidden(true) // decorative; the "Alarm set" text carries the meaning
                    VStack(alignment: .leading, spacing: 1) {
                        Text(OBALoc("stop_page.alarm.set_title", value: "Alarm set", comment: "Title of the set-alarm info row"))
                            .font(.subheadline.weight(.bold))
                        Text(String(format: OBALoc("stop_page.alarm.buzz_fmt", value: "Buzz %d min before it arrives", comment: "Subtitle of the set-alarm info row. %d is lead-time minutes."), leadTimeMinutes))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !isAccessibilitySize {
                        changeCancelButtons
                    }
                }
                if isAccessibilitySize {
                    // Side by side below the label when both fit; at the
                    // largest sizes each becomes its own full-width row.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            changeCancelButtons
                        }
                        VStack(spacing: 10) {
                            changeCancelButtons
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
                }
            }
        }
    }

    /// Change + Cancel, shared by the inline (default) and stacked
    /// (accessibility-size) placements.
    @ViewBuilder
    private var changeCancelButtons: some View {
        Button(OBALoc("stop_page.alarm.change", value: "Change", comment: "Re-presents the alarm time picker for an existing alarm"), action: onChange)
            .buttonStyle(.bordered)
        Button(Strings.cancel, role: .destructive, action: onCancel)
            .buttonStyle(.bordered)
    }
}
