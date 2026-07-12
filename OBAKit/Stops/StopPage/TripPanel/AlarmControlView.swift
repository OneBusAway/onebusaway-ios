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
/// with Dynamic Type via `@ScaledMetric`.
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
                        .accessibilityHidden(true) // decorative; the "Alarm set" text carries the meaning
                    VStack(alignment: .leading, spacing: 1) {
                        Text(OBALoc("stop_page.alarm.set_title", value: "Alarm set", comment: "Title of the set-alarm info row"))
                            .font(.subheadline.weight(.bold))
                        Text(String(format: OBALoc("stop_page.alarm.buzz_fmt", value: "Buzz %d min before it arrives", comment: "Subtitle of the set-alarm info row. %d is lead-time minutes."), leadTimeMinutes))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !editing && !isAccessibilitySize {
                        changeCancelButtons
                    }
                }
                if !editing && isAccessibilitySize {
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
                if editing {
                    editingControls
                }
            }
        }
    }

    /// Change + Cancel, shared by the inline (default) and stacked
    /// (accessibility-size) placements.
    @ViewBuilder
    private var changeCancelButtons: some View {
        Button(OBALoc("stop_page.alarm.change", value: "Change", comment: "Reveals the alarm lead-time stepper")) {
            pendingMinutes = leadTimeMinutes
            editing = true
        }
        .buttonStyle(.bordered)
        Button(Strings.cancel, role: .destructive, action: onCancel)
            .buttonStyle(.bordered)
    }

    /// The lead-time stepper row. At accessibility sizes the label sits above
    /// the stepper + Done controls instead of sharing their line.
    @ViewBuilder
    private var editingControls: some View {
        let label = Text(OBALoc("stop_page.alarm.minutes_before", value: "Minutes before", comment: "Stepper label"))
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
        let controls = HStack {
            Stepper(value: $pendingMinutes, in: AlarmLeadTime.minimumMinutes...max(AlarmLeadTime.minimumMinutes, maxLeadTime)) {
                Text("\(pendingMinutes)m").font(.subheadline.weight(.heavy)).monospacedDigit()
            }
            .fixedSize()
            // The visible "Minutes before" caption is a separate Text, so the
            // stepper's own label would otherwise be just "5m" — restate the
            // label and speak the value in full.
            .accessibilityLabel(OBALoc("stop_page.alarm.minutes_before", value: "Minutes before", comment: "Stepper label"))
            .accessibilityValue(String(format: OBALoc("stop_page.alarm.a11y_minutes_fmt", value: "%d minutes", comment: "VoiceOver value of the alarm lead-time stepper. %d is the number of minutes."), pendingMinutes))
            Button(OBALoc("stop_page.alarm.done", value: "Done", comment: "Commits the lead-time change")) {
                editing = false
                onChange(pendingMinutes)
            }
            .buttonStyle(.borderedProminent)
            .tint(onTimeColor)
        }

        if isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                label
                controls
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
        } else {
            HStack {
                label
                Spacer()
                controls
            }
            .padding(.top, 10)
        }
    }
}
