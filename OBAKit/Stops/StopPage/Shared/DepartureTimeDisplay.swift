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
/// The two are compared *as formatted strings* rather than as dates, because the
/// question being answered is "would these render identically?", not "are these
/// the same minute?". A prediction twenty seconds off the timetable is a
/// different `Date` but the same clock text, and rendering "10:42 AM 10:42 AM"
/// with one struck through reads as a bug. The rule therefore tracks whatever
/// `Formatters.timeFormatter` renders, deliberately — if that ever coarsens, the
/// strikethrough should disappear along with the visible difference.
///
/// Comparing after formatting also catches the case `ScheduleStatus` misses: a
/// deviation inside its ±1.5 minute "on time" band still lands on a different
/// minute, and the rider still needs the corrected time.
struct DepartureTimeDisplay: Equatable {
    /// The time the rider should act on: the prediction when there is one,
    /// the timetable otherwise.
    let expectedTimeText: String

    /// The timetable time, present only when it differs from `expectedTimeText`.
    /// Rendered struck through, ahead of the expected time.
    let scheduledTimeText: String?

    init(scheduledDate: Date, expectedDate: Date, isRealTime: Bool, formatters: Formatters) {
        // `isRealTime` gates on the feed's own `predicted` flag rather than on the
        // two dates differing: a payload can carry a prediction while declaring
        // itself unpredicted, and `DepartureStatus` refuses to trust that too.
        // When it's false the prediction is ignored outright, so there is nothing
        // to strike through and one format call answers both properties. Equal
        // dates necessarily format alike, so that case short-circuits here as
        // well without disturbing the compare-as-rendered rule above.
        guard isRealTime, expectedDate != scheduledDate else {
            self.expectedTimeText = formatters.timeFormatter.string(from: scheduledDate)
            self.scheduledTimeText = nil
            return
        }

        let expected = formatters.timeFormatter.string(from: expectedDate)
        let scheduled = formatters.timeFormatter.string(from: scheduledDate)

        self.expectedTimeText = expected
        self.scheduledTimeText = scheduled == expected ? nil : scheduled
    }

    init(arrivalDeparture: ArrivalDeparture, formatters: Formatters) {
        self.init(
            scheduledDate: arrivalDeparture.scheduledDate,
            expectedDate: arrivalDeparture.arrivalDepartureDate,
            isRealTime: arrivalDeparture.predicted,
            formatters: formatters
        )
    }

    /// Spoken equivalent of the strikethrough, which VoiceOver cannot perceive.
    ///
    /// Computed rather than stored: the render path never reads it, and building
    /// it eagerly would charge every row a bundle lookup for a string most
    /// people never hear.
    var accessibilityTimeDescription: String {
        guard let scheduledTimeText else {
            let fmt = OBALoc(
                "stop_page.time.a11y_at_fmt",
                value: "at %@",
                comment: "VoiceOver clause naming the clock time of a departure. %@ is the time."
            )
            return String(format: fmt, expectedTimeText)
        }

        let fmt = OBALoc(
            "stop_page.time.a11y_rescheduled_fmt",
            value: "scheduled %1$@, now expected %2$@",
            comment: "VoiceOver clause for a departure whose real-time prediction differs from its scheduled time. %1$@ is the scheduled time, %2$@ the predicted time."
        )
        return String(format: fmt, scheduledTimeText, expectedTimeText)
    }
}

/// Renders a `DepartureTimeDisplay`: one clock time, or the struck-through
/// scheduled time followed by the corrected one.
///
/// Deliberately styling-free apart from the strikethrough and the recessive
/// tint on the scheduled time — font and foreground style are inherited, so the
/// call sites keep the type scale they already had. Concatenated `Text` rather
/// than a stack so the pair wraps as ordinary text at large Dynamic Type sizes.
struct DepartureTimeText: View {
    let display: DepartureTimeDisplay

    var body: some View {
        time
            .monospacedDigit()
            // Every consumer speaks `accessibilityTimeDescription` in its own
            // combined label (those parents use `children: .ignore`, which drops
            // child labels outright), and a strikethrough is inaudible, so
            // leaving this visible would announce two unrelated bare times.
            .accessibilityHidden(true)
    }

    private var time: Text {
        guard let scheduledTimeText = display.scheduledTimeText else {
            return Text(display.expectedTimeText)
        }

        return Text(scheduledTimeText).strikethrough().foregroundStyle(.secondary)
            + Text(" ")
            + Text(display.expectedTimeText)
    }
}
