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
    /// When set, the number ticks on its own. Stop-page rows keep passing
    /// `minutes` only.
    public var departure: Date?
    /// Drawn on the Lock Screen, which can't tick our own `8m` style (#1583):
    /// there `TickingCountdownText` ticks it with Apple's format style instead.
    public var isLiveActivity: Bool = false

    public init(minutes: Int, isRealTime: Bool, color: Color, emphasized: Bool = true) {
        self.minutes = minutes
        self.isRealTime = isRealTime
        self.color = color
        self.emphasized = emphasized
        self.departure = nil
    }

    public init(departure: Date, isRealTime: Bool, color: Color, emphasized: Bool = true, isLiveActivity: Bool = false) {
        self.minutes = 0
        self.isRealTime = isRealTime
        self.color = color
        self.emphasized = emphasized
        self.departure = departure
        self.isLiveActivity = isLiveActivity
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 2) {
            countdownLabel
                .font(emphasized ? .system(.title2, design: .rounded, weight: .heavy) : .system(.callout, design: .rounded, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(color)
            RealtimeGlyph(isRealTime: isRealTime, color: color, size: emphasized ? 11 : 9)
                .padding(.top, 1)
        }
        .accessibilityHidden(true)
    }

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    @ViewBuilder
    private var countdownLabel: some View {
        if let departure, isLiveActivity {
            TickingCountdownText(
                departure: departure,
                font: emphasized ? .system(.title2, design: .rounded, weight: .heavy) : .system(.callout, design: .rounded, weight: .heavy),
                color: color
            )
        } else if let departure {
            let style = TripCountdownFormatStyle(departure: departure)
            // Reduced luminance redacts a custom style's digits to dashes, so
            // the dim watch face shows a static snapshot instead.
            if isLuminanceReduced {
                Text(style.format(Date()))
            } else {
                Text(.currentDate, format: style)
            }
        } else {
            Text(minutes == 0 ? OBALoc("stop_page.countdown.now", value: "NOW", comment: "Shown in place of the minutes countdown when the vehicle is departing now") : Formatters.shortMinutesText(minutes))
        }
    }
}
