//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The dashed reachability divider in chronological mode: everything above is
/// "just missed", everything below is catchable on foot (§4.5).
struct WalkLineDivider: View {
    let walkMinutes: Int

    private var text: String {
        let fmt = OBALoc("stop_page.walk_divider_fmt", value: "%d MIN WALK — CATCH BELOW", comment: "Divider between departures you'd miss on foot and ones you can still catch. %d is the walk time in minutes.")
        return String(format: fmt, walkMinutes)
    }

    var body: some View {
        HStack(spacing: 10) {
            dash
            Label(text, systemImage: "figure.walk")
                .font(.caption.weight(.heavy))
                .foregroundStyle(.orange)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            dash
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: OBALoc("stop_page.walk_divider_a11y_fmt", value: "Departures above this point leave sooner than your %d minute walk to the stop", comment: "VoiceOver description of the walk divider. %d is walk minutes."), walkMinutes))
    }

    private var dash: some View {
        Line()
            .stroke(style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
            .foregroundStyle(.orange)
            .frame(height: 2)
            .frame(maxWidth: .infinity)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}
