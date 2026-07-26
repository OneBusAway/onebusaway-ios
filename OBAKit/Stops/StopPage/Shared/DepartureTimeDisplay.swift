//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The clock time(s) shown on a departure row. When real-time data moves a trip
/// off its timetable the row shows both: the scheduled time struck through, then
/// the time the rider should actually act on.
///
/// The two are compared *as formatted strings* rather than as dates. A prediction
/// twenty seconds off the timetable is a different `Date` but the same clock
/// minute, and rendering "10:42 AM 10:42 AM" with one struck through reads as a
/// bug. Comparing after formatting also catches the case `ScheduleStatus` misses:
/// a deviation inside its ±1.5 minute "on time" band still lands on a different
/// minute, and the rider still needs the corrected time.
struct DepartureTimeDisplay {
    /// The time the rider should act on: the prediction when there is one,
    /// the timetable otherwise.
    let expectedTimeText: String

    /// The timetable time, present only when it differs from `expectedTimeText`.
    /// Rendered struck through, ahead of the expected time.
    let scheduledTimeText: String?

    /// Spoken equivalent of the strikethrough, which VoiceOver cannot perceive.
    let accessibilityTimeDescription: String

    init(scheduledDate: Date, expectedDate: Date, isRealTime: Bool, formatters: Formatters) {
        let expected = formatters.timeFormatter.string(from: isRealTime ? expectedDate : scheduledDate)
        let scheduled = formatters.timeFormatter.string(from: scheduledDate)

        self.expectedTimeText = expected
        self.scheduledTimeText = (isRealTime && scheduled != expected) ? scheduled : nil

        if let scheduledTimeText {
            let fmt = OBALoc(
                "stop_page.time.a11y_rescheduled_fmt",
                value: "scheduled %1$@, now expected %2$@",
                comment: "VoiceOver clause for a departure whose real-time prediction differs from its scheduled time. %1$@ is the scheduled time, %2$@ the predicted time."
            )
            self.accessibilityTimeDescription = String(format: fmt, scheduledTimeText, expected)
        }
        else {
            let fmt = OBALoc(
                "stop_page.time.a11y_at_fmt",
                value: "at %@",
                comment: "VoiceOver clause naming the clock time of a departure. %@ is the time."
            )
            self.accessibilityTimeDescription = String(format: fmt, expected)
        }
    }

    init(arrivalDeparture: ArrivalDeparture, formatters: Formatters) {
        self.init(
            scheduledDate: arrivalDeparture.scheduledDate,
            expectedDate: arrivalDeparture.arrivalDepartureDate,
            isRealTime: arrivalDeparture.predicted,
            formatters: formatters
        )
    }
}

/// Renders a `DepartureTimeDisplay`: one clock time, or the struck-through
/// scheduled time followed by the corrected one.
///
/// Deliberately styling-free apart from the strikethrough and the recessive
/// tint on the scheduled time — font and foreground style are inherited, so the
/// five call sites keep the type scale they already had.
struct DepartureTimeText: View {
    let display: DepartureTimeDisplay

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Unary root so the enclosing List rows keep their fast path.
        Group {
            if let scheduledTimeText = display.scheduledTimeText {
                // Two times don't fit side by side once the text is large enough,
                // so stack them the way the rows themselves stack.
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 1) {
                        scheduled(scheduledTimeText)
                        expected
                    }
                }
                else {
                    HStack(spacing: 4) {
                        scheduled(scheduledTimeText)
                        expected
                    }
                }
            }
            else {
                expected
            }
        }
        .monospacedDigit()
        // Every consumer speaks `accessibilityTimeDescription` in its own
        // combined label; a strikethrough is inaudible, so leaving these
        // visible would announce two bare times with no relationship.
        .accessibilityHidden(true)
    }

    private var expected: Text {
        Text(display.expectedTimeText)
    }

    private func scheduled(_ text: String) -> some View {
        Text(text)
            .strikethrough()
            .foregroundStyle(.secondary)
    }
}
