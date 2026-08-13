//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

/// The "{n}m" countdown with its real-time glyph. Public so the widget extension can use it.
public struct CountdownView: View {
    public let minutes: Int
    public let isRealTime: Bool
    public let color: Color
    /// `true` = card-header size, `false` = compact.
    public var emphasized: Bool = true

    public init(minutes: Int, isRealTime: Bool, color: Color, emphasized: Bool = true) {
        self.minutes = minutes
        self.isRealTime = isRealTime
        self.color = color
        self.emphasized = emphasized
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 2) {
            Text(minutes == 0 ? OBALoc("stop_page.countdown.now", value: "NOW", comment: "Shown in place of the minutes countdown when the vehicle is departing now") : "\(minutes)m")
                .font(emphasized ? .system(.title2, design: .rounded, weight: .heavy) : .system(.callout, design: .rounded, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(color)
            RealtimeGlyph(isRealTime: isRealTime, color: color, size: emphasized ? 11 : 9)
                .padding(.top, 1)
        }
        .accessibilityHidden(true)
    }
}
