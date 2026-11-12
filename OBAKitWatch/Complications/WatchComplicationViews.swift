//
//  WatchComplicationViews.swift
//  OBAKitWatch
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore
import SwiftUI
import WidgetKit

/// Localized strings for watchOS complications (`OBAKitWatch/Strings`).
public enum WatchComplicationStrings {
    public static var galleryDisplayName: String {
        OBALoc("complications.gallery.display_name", value: "Next Departure", comment: "Display name for the next-departure Apple Watch complication")
    }

    public static var galleryDescription: String {
        OBALoc("complications.gallery.description", value: "See the next upcoming departure for your top bookmark.", comment: "Description for the next-departure Apple Watch complication")
    }

    public static var noDepartures: String {
        OBALoc("complications.no_departures", value: "No departures", comment: "Short complication fallback when no upcoming departures exist")
    }

    public static func noDepartures(inNextMinutes minutes: Int) -> String {
        let fmt = OBALoc("complications.no_departures_in_next_minutes_fmt", value: "No departures in the next %d min", comment: "Rectangular complication fallback when no departures are expected soon. %d is minutes.")
        return String(format: fmt, locale: .current, minutes)
    }

    public static var noBookmarksHint: String {
        OBALoc("complications.no_bookmarks_hint", value: "Favorite a bookmark on iPhone.", comment: "Hint on rectangular watch complication when no favorite bookmarks are synced")
    }

    public static var unavailable: String {
        OBALoc("complications.unavailable", value: "Unavailable", comment: "Short complication fallback when departure data could not be loaded")
    }
}

/// Reusable watchOS complication view supporting `.accessoryCircular`,
/// `.accessoryRectangular`, `.accessoryInline`, and `.accessoryCorner`.
public struct WatchNextDepartureComplicationView: View {
    public let entry: WatchComplicationEntry
    public let formatters: Formatters

    @Environment(\.widgetFamily) private var widgetFamily
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.locale) private var locale

    public init(entry: WatchComplicationEntry, formatters: Formatters) {
        self.entry = entry
        self.formatters = formatters
    }

    private var isFullColor: Bool {
        widgetRenderingMode == .fullColor
    }

    public var body: some View {
        switch widgetFamily {
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        case .accessoryInline:
            inlineView
        #if os(watchOS)
        case .accessoryCorner:
            cornerView
        #endif
        default:
            rectangularView
        }
    }

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            switch entry.state {
            case .departure(let departure, _):
                ComplicationCircularDepartureContent(
                    departure: departure,
                    referenceDate: entry.date,
                    formatters: formatters,
                    isFullColor: isFullColor
                )
                .widgetAccentable()

            case .noDepartures(let bookmark):
                ComplicationCircularFallbackContent(
                    routeShortName: bookmark.routeShortName,
                    systemImage: "bus.fill",
                    accessibilityText: "\(bookmark.displayTitle), \(WatchComplicationStrings.noDepartures)"
                )
                .widgetAccentable()

            case .unavailable(let bookmark):
                ComplicationCircularFallbackContent(
                    routeShortName: bookmark.routeShortName,
                    systemImage: "arrow.clockwise",
                    accessibilityText: "\(bookmark.displayTitle), \(WatchComplicationStrings.unavailable)"
                )
                .widgetAccentable()

            case .noBookmarks:
                ComplicationCircularFallbackContent(
                    routeShortName: nil,
                    systemImage: "bookmark",
                    accessibilityText: Strings.emptyBookmarkTitle
                )
                .widgetAccentable()
            }
        }
    }

    #if os(watchOS)
    private var cornerView: some View {
        Group {
            switch entry.state {
            case .departure(let departure, _):
                Text(verbatim: departure.routeShortName)
                    .font(.system(.headline, design: .rounded, weight: .heavy))
                    .widgetAccentable()
                    .widgetLabel {
                        ComplicationPresentation.countdownText(
                            for: departure,
                            at: entry.date,
                            isLuminanceReduced: isLuminanceReduced,
                            locale: locale
                        )
                        .monospacedDigit()
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(ComplicationPresentation.departureAccessibilityLabel(
                        for: departure,
                        formatters: formatters,
                        isLuminanceReduced: isLuminanceReduced,
                        locale: locale
                    ))
                    .accessibilityAddTraits(.updatesFrequently)

            case .noDepartures(let bookmark):
                Image(systemName: "bus.fill")
                    .widgetAccentable()
                    .widgetLabel {
                        Text(verbatim: "\(bookmark.displayTitle) · --")
                    }

            case .unavailable(let bookmark):
                Image(systemName: "arrow.clockwise")
                    .widgetAccentable()
                    .widgetLabel {
                        Text(verbatim: "\(bookmark.displayTitle) · --")
                    }

            case .noBookmarks:
                Image(systemName: "bookmark")
                    .widgetAccentable()
                    .widgetLabel {
                        Text(verbatim: Strings.emptyBookmarkTitle)
                    }
            }
        }
    }
    #endif

    private var rectangularView: some View {
        Group {
            switch entry.state {
            case .departure(let departure, _):
                ComplicationRectangularDepartureContent(
                    departure: departure,
                    referenceDate: entry.date,
                    formatters: formatters,
                    isFullColor: isFullColor
                )
                .widgetAccentable(!isFullColor)

            case .noDepartures(let bookmark):
                ComplicationRectangularFallbackContent(
                    title: bookmark.displayTitle,
                    subtitle: WatchComplicationStrings.noDepartures(inNextMinutes: 60),
                    systemImage: nil
                )
                .widgetAccentable()

            case .unavailable(let bookmark):
                ComplicationRectangularFallbackContent(
                    title: bookmark.displayTitle,
                    subtitle: WatchComplicationStrings.unavailable,
                    systemImage: nil
                )
                .widgetAccentable()

            case .noBookmarks:
                ComplicationRectangularFallbackContent(
                    title: Strings.emptyBookmarkTitle,
                    subtitle: WatchComplicationStrings.noBookmarksHint,
                    systemImage: "bookmark"
                )
                .widgetAccentable()
            }
        }
    }

    private var inlineView: some View {
        Group {
            switch entry.state {
            case .departure(let departure, _):
                ComplicationPresentation.inlineDepartureText(
                    for: departure,
                    at: entry.date,
                    isLuminanceReduced: isLuminanceReduced,
                    locale: locale
                )
                .accessibilityLabel(ComplicationPresentation.departureAccessibilityLabel(
                    for: departure,
                    formatters: formatters,
                    isLuminanceReduced: isLuminanceReduced,
                    locale: locale
                ))
                .accessibilityAddTraits(.updatesFrequently)

            case .noDepartures(let bookmark):
                Text(verbatim: "\(bookmark.displayTitle) · \(WatchComplicationStrings.noDepartures)")

            case .unavailable(let bookmark):
                Text(verbatim: "\(bookmark.displayTitle) · \(WatchComplicationStrings.unavailable)")

            case .noBookmarks:
                Text(verbatim: Strings.emptyBookmarkTitle)
            }
        }
    }
}

/// Reusable watchOS Widget configuration for the next-departure complication.
public struct WatchNextDepartureComplicationWidget: Widget {
    public let kind: String = "WatchNextDepartureComplication"

    private let formatters = Formatters(
        locale: .autoupdatingCurrent,
        calendar: .autoupdatingCurrent,
        themeColors: .shared
    )

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: WatchComplicationTimelineProvider()
        ) { entry in
            WatchNextDepartureComplicationView(entry: entry, formatters: formatters)
                .containerBackground(.fill.quaternary, for: .widget)
        }
        .configurationDisplayName(WatchComplicationStrings.galleryDisplayName)
        .description(WatchComplicationStrings.galleryDescription)
        .supportedFamilies(supportedFamilies)
    }

    private var supportedFamilies: [WidgetFamily] {
        #if os(watchOS)
        [.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner]
        #else
        [.accessoryCircular, .accessoryRectangular, .accessoryInline]
        #endif
    }
}
