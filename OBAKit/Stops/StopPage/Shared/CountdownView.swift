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
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(minutes)m")
                .font(emphasized ? .system(.title, design: .rounded, weight: .heavy) : .system(.body, design: .rounded, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(color)
            RealtimeGlyph(isRealTime: isRealTime, color: color, size: emphasized ? 13 : 11)
        }
        .accessibilityElement(children: .ignore)
    }
}
