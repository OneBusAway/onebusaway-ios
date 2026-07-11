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
/// once set, an info row with Change (inline stepper) and Cancel.
///
/// Text uses Dynamic Type text styles; the fixed bell-circle dimension scales
/// with `@ScaledMetric` (standing amendment 1).
struct AlarmControlView: View {
    let alarmIsSet: Bool
    let leadTimeMinutes: Int
    let maxLeadTime: Int   // min(15, minutesUntilDeparture - 1)
    let onSet: () -> Void
    let onCancel: () -> Void
    let onChange: (Int) -> Void

    @State private var editing = false
    @State private var pendingMinutes: Int = AlarmLeadTime.defaultMinutes

    /// The bell circle grows with Dynamic Type the way the grouped alarm badge
    /// does (standing amendment 1).
    @ScaledMetric(relativeTo: .body) private var bellCircleSize: CGFloat = 32

    private var onTimeColor: Color { Color(uiColor: ThemeColors.shared.departureOnTime) }

    var body: some View {
        VStack(spacing: 0) {
            if !alarmIsSet {
                Button(action: onSet) {
                    Label(OBALoc("stop_page.alarm.set", value: "Set an alarm", comment: "Primary alarm button in the trip panel"), systemImage: "bell")
                        .font(.subheadline.weight(.heavy))
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.borderedProminent)
                .tint(onTimeColor)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "bell.fill")
                        .foregroundStyle(onTimeColor)
                        .frame(width: bellCircleSize, height: bellCircleSize)
                        .background(onTimeColor.opacity(0.14), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(OBALoc("stop_page.alarm.set_title", value: "Alarm set", comment: "Title of the set-alarm info row"))
                            .font(.subheadline.weight(.bold))
                        Text(String(format: OBALoc("stop_page.alarm.buzz_fmt", value: "Buzz %d min before it arrives", comment: "Subtitle of the set-alarm info row. %d is lead-time minutes."), leadTimeMinutes))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !editing {
                        Button(OBALoc("stop_page.alarm.change", value: "Change", comment: "Reveals the alarm lead-time stepper")) {
                            pendingMinutes = leadTimeMinutes
                            editing = true
                        }
                        .buttonStyle(.bordered)
                        Button(Strings.cancel, role: .destructive, action: onCancel)
                            .buttonStyle(.bordered)
                    }
                }
                if editing {
                    HStack {
                        Text(OBALoc("stop_page.alarm.minutes_before", value: "Minutes before", comment: "Stepper label"))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Stepper(value: $pendingMinutes, in: AlarmLeadTime.minimumMinutes...max(AlarmLeadTime.minimumMinutes, maxLeadTime)) {
                            Text("\(pendingMinutes)m").font(.subheadline.weight(.heavy)).monospacedDigit()
                        }
                        .fixedSize()
                        Button(OBALoc("stop_page.alarm.done", value: "Done", comment: "Commits the lead-time change")) {
                            editing = false
                            onChange(pendingMinutes)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(onTimeColor)
                    }
                    .padding(.top, 10)
                }
            }
        }
    }
}
