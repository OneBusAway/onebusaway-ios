//
//  TickingCountdownText.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import SwiftUI

/// "in 8 minutes" / "now" that self-updates on a Live Activity, using a
/// SwiftUI system style (see `liveFormat`). Dim Lock Screen draws a static
/// snapshot of the same wording.
///
/// `opacity` and `accessibilityLabel` are first-class so Live Activity stale
/// chrome (#1379) can compose on this type instead of re-wrapping modifiers
/// around every call site.
///
/// See: https://github.com/OneBusAway/onebusaway-ios/issues/1187
public struct TickingCountdownText: View {
    public let departure: Date
    public let font: Font
    public let color: Color
    /// Stale Live Activity chrome dims minutes via `LiveActivityStaleChrome.contentOpacity`.
    public let opacity: Double
    /// When set (e.g. minimal Island + stale warning), replaces what VoiceOver
    /// reads. When `nil`, it reads the countdown, which is already spelled out.
    public let accessibilityLabel: String?

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.locale) private var locale

    public init(
        departure: Date,
        font: Font,
        color: Color,
        opacity: Double = 1.0,
        accessibilityLabel: String? = nil
    ) {
        self.departure = departure
        self.font = font
        self.color = color
        self.opacity = opacity
        self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
        let label = Self.spokenText(departure: departure, isLuminanceReduced: isLuminanceReduced, locale: locale)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(color)
            .opacity(opacity)

        if let accessibilityLabel {
            label.accessibilityLabel(accessibilityLabel)
        } else {
            label
        }
    }

    /// "in 8 minutes" / "now", ticking on its own.
    ///
    /// It must be one of SwiftUI's system styles. The Lock Screen renders a
    /// ticking `Text` out of process; at full brightness it drew a custom
    /// `DiscreteFormatStyle` as a redacted placeholder card (#1583).
    public static func liveFormat(departure: Date, locale: Locale = .autoupdatingCurrent) -> SystemFormatStyle.DateReference {
        SystemFormatStyle.DateReference(to: departure, allowedFields: [.minute], maxFieldCount: 1, thresholdField: .minute)
            .locale(locale)
    }

    /// What `liveFormat` says at `now`, for anything that can't tick: the dim
    /// Lock Screen, and labels baked into a string.
    public static func snapshot(departure: Date, now: Date, locale: Locale = .autoupdatingCurrent) -> String {
        String(liveFormat(departure: departure, locale: locale).format(now).characters)
    }

    /// The countdown as a `Text`: ticking, or a static snapshot under reduced
    /// luminance. Public so a combined accessibility label (the Live Activity
    /// card) can splice it in.
    public static func spokenText(departure: Date, isLuminanceReduced: Bool = false, locale: Locale = .autoupdatingCurrent) -> Text {
        if isLuminanceReduced {
            return Text(verbatim: snapshot(departure: departure, now: Date(), locale: locale))
        }
        return Text(.currentDate, format: liveFormat(departure: departure, locale: locale))
    }
}
