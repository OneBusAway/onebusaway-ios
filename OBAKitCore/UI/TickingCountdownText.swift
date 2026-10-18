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

/// `8m` that self-updates on a Live Activity, read by VoiceOver as "in 8
/// minutes". Both use Apple's format styles (see `visibleFormat` and
/// `spokenFormat`); dim Lock Screen draws a static snapshot of the same text.
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
    /// reads. When `nil`, it reads the spelled-out countdown ("in 8 minutes"),
    /// never the visible `8m`, which it would say as "8 meters".
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
        let label = Group {
            if isLuminanceReduced {
                Text(verbatim: Self.snapshot(departure: departure, now: Date(), locale: locale))
            } else {
                Text(.dateRange(endingAt: departure), format: Self.visibleFormat(locale: locale))
            }
        }
        .font(font)
        .monospacedDigit()
        .foregroundStyle(color)
        .opacity(opacity)

        if let accessibilityLabel {
            label.accessibilityLabel(accessibilityLabel)
        } else {
            label.accessibilityLabel(Self.spokenText(departure: departure, isLuminanceReduced: isLuminanceReduced, locale: locale))
        }
    }

    // MARK: - Visible: "8m"

    /// `8m`, ticking on its own over the time left before departure. Whole
    /// minutes, truncated like the Stop page; `0m` in the final minute.
    ///
    /// It must be one of Apple's format styles. The Lock Screen renders a
    /// ticking `Text` out of process; at full brightness it drew our own
    /// custom `DiscreteFormatStyle` as a redacted placeholder card (#1583).
    public static func visibleFormat(locale: Locale = .autoupdatingCurrent) -> Date.ComponentsFormatStyle {
        Date.ComponentsFormatStyle(style: .narrow, locale: locale, fields: [.minute])
    }

    /// What `visibleFormat` shows at `now`, for the dim Lock Screen.
    public static func snapshot(departure: Date, now: Date, locale: Locale = .autoupdatingCurrent) -> String {
        // A backwards range traps; a departed arrival reads as no time left.
        visibleFormat(locale: locale).format(now..<max(now, departure))
    }

    // MARK: - Spoken: "in 8 minutes"

    /// "in 8 minutes" / "now", ticking on its own. A SwiftUI system style, for
    /// the same out-of-process reason as `visibleFormat`.
    public static func spokenFormat(departure: Date, locale: Locale = .autoupdatingCurrent) -> SystemFormatStyle.DateReference {
        SystemFormatStyle.DateReference(to: departure, allowedFields: [.minute], maxFieldCount: 1, thresholdField: .minute)
            .locale(locale)
    }

    /// What `spokenFormat` says at `now`, for labels baked into a string.
    public static func spokenSnapshot(departure: Date, now: Date, locale: Locale = .autoupdatingCurrent) -> String {
        String(spokenFormat(departure: departure, locale: locale).format(now).characters)
    }

    /// The spoken countdown as a `Text`: ticking, or a static snapshot under
    /// reduced luminance. Public so a combined accessibility label (the Live
    /// Activity card) can splice it in.
    public static func spokenText(departure: Date, isLuminanceReduced: Bool = false, locale: Locale = .autoupdatingCurrent) -> Text {
        if isLuminanceReduced {
            return Text(verbatim: spokenSnapshot(departure: departure, now: Date(), locale: locale))
        }
        return Text(.currentDate, format: spokenFormat(departure: departure, locale: locale))
    }
}
