//
//  LiveActivityCountdownView.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

/// Live Activity countdown that ticks on its own via a bounded timer interval.
///
/// Unlike `CountdownView`'s static `"\(minutes)m"` string (which only changes when
/// a push or local `Activity.update` arrives), the system redraws `.timer` text
/// as the departure approaches — so the Lock Screen / Dynamic Island stay honest
/// even when keepalive pushes are sparse (#1187).
public struct LiveActivityCountdownView: View {
    public let departureDate: Date
    public let isRealTime: Bool
    public let color: Color
    /// `true` = card-header size, `false` = compact chips / island.
    public var emphasized: Bool = true

    public init(departureDate: Date, isRealTime: Bool, color: Color, emphasized: Bool = true) {
        self.departureDate = departureDate
        self.isRealTime = isRealTime
        self.color = color
        self.emphasized = emphasized
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 2) {
            countdownLabel
                .font(emphasized ? .system(.title2, design: .rounded, weight: .heavy) : .system(.callout, design: .rounded, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(color)
                .multilineTextAlignment(.trailing)
            RealtimeGlyph(isRealTime: isRealTime, color: color, size: emphasized ? 11 : 9)
                .padding(.top, 1)
        }
        .accessibilityHidden(true)
    }

    private var countdownLabel: some View {
        Text(
            timerInterval: LiveActivityCountdown.boundedTimerInterval(departureDate: departureDate),
            pauseTime: departureDate,
            countsDown: true,
            showsHours: false
        )
    }
}

/// Pure helpers for Live Activity countdown presentation (#1187).
public enum LiveActivityCountdown {
    /// Returns a countdown interval that reaches zero at `departureDate` and
    /// never becomes an elapsed-time counter after that instant.
    public static func boundedTimerInterval(
        departureDate: Date,
        now: Date = Date()
    ) -> ClosedRange<Date> {
        min(now, departureDate)...departureDate
    }
}
