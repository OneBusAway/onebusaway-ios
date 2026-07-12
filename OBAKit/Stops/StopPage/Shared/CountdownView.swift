//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

/// The "{n}m" countdown with its real-time glyph. Color encodes adherence
/// status, never route (§4.3).
struct CountdownView: View {
    let minutes: Int
    let isRealTime: Bool
    let color: Color
    /// true = card-header size (grouped card / chrono row), false = compact.
    var emphasized: Bool = true

    var body: some View {
        // Top-aligned so the glyph floats at the number's top-right corner
        // like a superscript, per the comps — not baseline-aligned beside it.
        HStack(alignment: .top, spacing: 2) {
            Text(minutes == 0 ? OBALoc("stop_page.countdown.now", value: "NOW", comment: "Shown in place of the minutes countdown when the vehicle is departing now") : "\(minutes)m")
                .font(emphasized ? .system(.title2, design: .rounded, weight: .heavy) : .system(.callout, design: .rounded, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(color)
            RealtimeGlyph(isRealTime: isRealTime, color: color, size: emphasized ? 11 : 9)
                .padding(.top, 1)
        }
        // Hidden outright rather than an empty `children: .ignore` element:
        // every consumer (departure rows, grouped cards) speaks the countdown
        // in its own combined label, and a label-less element would otherwise
        // be a silent VoiceOver stop wherever an ancestor doesn't swallow it.
        .accessibilityHidden(true)
    }
}
