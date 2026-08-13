//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

/// Animated wave glyph for real-time trips, static clock for scheduled-only. Public so the widget can use it.
public struct RealtimeGlyph: View {
    public let isRealTime: Bool
    public let color: Color
    public var size: CGFloat = 14

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    public init(isRealTime: Bool, color: Color, size: CGFloat = 14) {
        self.isRealTime = isRealTime
        self.color = color
        self.size = size
    }

    public var body: some View {
        Image(systemName: isRealTime ? "dot.radiowaves.up.forward" : "clock")
            .font(.system(size: size * scale, weight: .semibold))
            .foregroundStyle(isRealTime ? color : Color(uiColor: .secondaryLabel))
            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isRealTime && !reduceMotion)
            .accessibilityHidden(true)
    }
}
