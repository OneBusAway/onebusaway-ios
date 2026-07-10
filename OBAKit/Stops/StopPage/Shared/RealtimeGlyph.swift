//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

/// The at-a-glance "is this tracked?" signal (§4.1): animated radiating waves
/// for live trips, a static outline clock for schedule-only. Uses an SF Symbol
/// variable-color effect so the system batches animation across the ~15
/// instances a full list shows — never per-instance repeatForever loops.
struct RealtimeGlyph: View {
    let isRealTime: Bool
    let color: Color
    var size: CGFloat = 14

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        // Unary root: one Image; the live/scheduled fork is symbol + modifier state.
        Image(systemName: isRealTime ? "dot.radiowaves.up.forward" : "clock")
            .font(.system(size: size * scale, weight: .semibold))
            .foregroundStyle(isRealTime ? color : Color(uiColor: .secondaryLabel))
            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isRealTime && !reduceMotion)
            .accessibilityHidden(true) // status is conveyed in the row's combined label
    }
}
