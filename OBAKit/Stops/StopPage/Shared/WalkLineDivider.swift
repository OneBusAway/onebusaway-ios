//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The dashed reachability divider in chronological mode: everything above is
/// "just missed", everything below is catchable at the user's current travel
/// mode (§4.5). `walkMinutes` is mode-aware — it's already bike time when Bike
/// Mode is on — so the label and icon have to say so too, or the divider would
/// tell a cyclist they have an implausibly fast "walk".
struct WalkLineDivider: View {
    let walkMinutes: Int
    var isBikeMode: Bool = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Matches the walk/bike pill on the header card (§4.5).
    private var lineColor: Color {
        Color(uiColor: isBikeMode ? ThemeColors.shared.blue : ThemeColors.shared.departureOnTime)
    }

    private var systemImage: String {
        isBikeMode ? "bicycle" : "figure.walk"
    }

    private var text: String {
        let fmt = isBikeMode
            ? OBALoc("stop_page.bike_divider_fmt", value: "%d MIN BIKE — CATCH BELOW", comment: "Divider between departures you'd miss on a bike and ones you can still catch. %d is the bike time in minutes.")
            : OBALoc("stop_page.walk_divider_fmt", value: "%d MIN WALK — CATCH BELOW", comment: "Divider between departures you'd miss on foot and ones you can still catch. %d is the walk time in minutes.")
        return String(format: fmt, walkMinutes)
    }

    private var accessibilityText: String {
        let fmt = isBikeMode
            ? OBALoc("stop_page.bike_divider_a11y_fmt", value: "Departures above this point leave sooner than your %d minute bike ride to the stop", comment: "VoiceOver description of the bike divider. %d is bike minutes.")
            : OBALoc("stop_page.walk_divider_a11y_fmt", value: "Departures above this point leave sooner than your %d minute walk to the stop", comment: "VoiceOver description of the walk divider. %d is walk minutes.")
        return String(format: fmt, walkMinutes)
    }

    var body: some View {
        // At accessibility sizes the flanking dashes go away — they'd squeeze
        // the label into a sliver — and the label becomes a full-width dashed
        // banner box that wraps at full size (minimum-scale-factor is not a
        // Dynamic Type strategy; the text must grow, not the row squeeze it).
        HStack(spacing: 10) {
            if dynamicTypeSize.isAccessibilitySize {
                Label(text, systemImage: systemImage)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(lineColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
                            .foregroundStyle(lineColor)
                    )
            } else {
                dash
                Label(text, systemImage: systemImage)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(lineColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    // The dashes are greedy (maxWidth: .infinity); without a
                    // higher priority the HStack squeezes the label instead of
                    // shortening the dashes.
                    .layoutPriority(1)
                dash
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var dash: some View {
        Line()
            .stroke(style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
            .foregroundStyle(lineColor)
            .frame(height: 2)
            .frame(maxWidth: .infinity)
    }

    nonisolated private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}

#Preview {
    List {
        WalkLineDivider(walkMinutes: 104)
        WalkLineDivider(walkMinutes: 8)
        WalkLineDivider(walkMinutes: 3, isBikeMode: true)
    }
}
