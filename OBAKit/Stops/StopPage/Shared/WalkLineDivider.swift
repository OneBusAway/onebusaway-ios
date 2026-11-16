//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The reachability divider in chronological mode: everything above is "just
/// missed", everything below is catchable at the user's current travel mode
/// (§4.5). A glass capsule — "4 min walk · at stop 8:20 PM" — that offers
/// directions to the stop when tapped.
///
/// `walkMinutes` is mode-aware — it's already bike time when Bike Mode is on —
/// so the label and icon have to say so too, or the divider would tell a
/// cyclist they have an implausibly fast "walk".
struct WalkLineDivider: View {
    let walkMinutes: Int
    var isBikeMode: Bool = false
    var directions: StopPillDirections = .none

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.obaFormatters) private var formatters

    private var pill: StopDirectionsPill { isBikeMode ? .bike : .walk }

    /// The on-time green or the bike-mode blue: the same fills as the header's
    /// walk and bike pills (§4.5). The fill token, not `departureOnTime`, because
    /// a white glyph sits on it: white on the text green is 2.0:1 in dark mode.
    private var tint: Color {
        Color(uiColor: isBikeMode ? ThemeColors.shared.blue : ThemeColors.shared.departureOnTimeFill)
    }

    /// Whether a tap does anything, which decides whether the glass reacts to it.
    private var isInteractive: Bool {
        pill.behavior(tripPlannerAvailable: directions.tripPlannerAvailable) != nil
    }

    private var minutesText: String { pill.text(minutes: walkMinutes) }

    private var accessibilityText: String {
        let fmt = isBikeMode
            ? OBALoc("stop_page.bike_divider_a11y_fmt", value: "Departures above this point leave sooner than your %d minute bike ride to the stop", comment: "VoiceOver description of the bike divider. %d is bike minutes.")
            : OBALoc("stop_page.walk_divider_a11y_fmt", value: "Departures above this point leave sooner than your %d minute walk to the stop", comment: "VoiceOver description of the walk divider. %d is walk minutes.")
        return String(format: fmt, walkMinutes)
    }

    var body: some View {
        // Ticks each minute so "at stop" keeps pace with the clock between
        // arrival refreshes.
        TimelineView(.everyMinute) { context in
            let atStop = Self.atStopText(
                arrival: context.date.addingTimeInterval(TimeInterval(walkMinutes * 60)),
                formatters: formatters
            )
            capsule(atStop: atStop)
                // Same sequence as the header's `StopTravelPill`: name the element,
                // then let `directionsAction` decide whether a tap does anything
                // and add the button trait, default action and hint if so.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText)
                .accessibilityValue(atStop)
                .directionsAction(pill, directions)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    /// One line where it fits. At accessibility sizes, or when a long
    /// translation won't fit, the capsule becomes a full-width rounded card
    /// and its two halves stack, so the text grows instead of truncating.
    @ViewBuilder
    private func capsule(atStop: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            stacked(atStop: atStop)
        } else {
            ViewThatFits(in: .horizontal) {
                inline(atStop: atStop)
                stacked(atStop: atStop)
            }
        }
    }

    private func inline(atStop: String) -> some View {
        HStack(spacing: 8) {
            glyph
            // One unwrappable line, so the capsule's width follows its content
            // (see `StopTravelPill` for what a List row does otherwise).
            HStack(spacing: 4) {
                Text(minutesText).fontWeight(.semibold)
                Text(verbatim: "·").foregroundStyle(.secondary)
                Text(atStop).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
        .font(.subheadline)
        .padding(.leading, 6)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .contentShape(Capsule())
        .regularGlassEffectIfAvailable(in: Capsule(), interactive: isInteractive)
    }

    private func stacked(atStop: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return HStack(spacing: 12) {
            glyph
            VStack(alignment: .leading, spacing: 2) {
                Text(minutesText).fontWeight(.semibold)
                Text(atStop).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.subheadline)
        .padding(12)
        .frame(maxWidth: .infinity)
        .contentShape(shape)
        .regularGlassEffectIfAvailable(in: shape, interactive: isInteractive)
    }

    private var glyph: some View {
        Image(systemName: pill.systemImage)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(tint, in: Circle())
            .accessibilityHidden(true)
    }

    /// "at stop 8:20 PM": when the rider would reach the stop if they left now.
    /// The clock is in the region's time zone, like the departure times around it.
    static func atStopText(arrival: Date, formatters: Formatters) -> String {
        String(
            format: OBALoc("stop_page.walk_divider.at_stop_fmt", value: "at stop %@", comment: "Second half of the walk divider: when the rider would reach the stop if they left now. %@ is a clock time, e.g. 8:20 PM."),
            formatters.formattedClockTime(arrival)
        )
    }
}

#Preview {
    List {
        WalkLineDivider(walkMinutes: 104)
        WalkLineDivider(walkMinutes: 8, directions: StopPillDirections(tripPlannerAvailable: true, perform: { _ in }))
        WalkLineDivider(walkMinutes: 3, isBikeMode: true)
    }
}
