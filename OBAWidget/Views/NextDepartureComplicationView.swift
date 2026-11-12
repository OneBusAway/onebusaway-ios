//
//  NextDepartureComplicationView.swift
//  OBAWidget
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore
import SwiftUI
import WidgetKit

/// Renders the next bookmarked departure for Lock Screen and Apple Watch
/// accessory complication families (`.accessoryCircular`,
/// `.accessoryRectangular`, and `.accessoryInline`).
struct NextDepartureComplicationView: View {
    let entry: BookmarkEntry
    let formatters: Formatters

    @Environment(\.widgetFamily) private var widgetFamily
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.locale) private var locale

    private var isFullColor: Bool {
        widgetRenderingMode == .fullColor
    }

    private var state: NextDepartureComplicationState {
        NextDepartureComplication.resolve(
            bookmarks: entry.bookmarks,
            departuresByBookmark: entry.departures,
            now: entry.date
        )
    }

    var body: some View {
        content
            .widgetURL(deepLinkURL)
    }

    private var deepLinkURL: URL? {
        guard let bookmark = state.bookmark else { return nil }
        return BookmarkEntry.deepLinkURL(stopID: bookmark.stopID, regionIdentifier: bookmark.regionIdentifier)
    }

    @ViewBuilder
    private var content: some View {
        switch widgetFamily {
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        case .accessoryInline:
            inlineView
        default:
            rectangularView
        }
    }

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            switch state {
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
                    accessibilityText: "\(bookmark.displayTitle), \(WidgetStrings.complicationNoDepartures)"
                )
                .widgetAccentable()

            case .unavailable(let bookmark):
                ComplicationCircularFallbackContent(
                    routeShortName: bookmark.routeShortName,
                    systemImage: "arrow.clockwise",
                    accessibilityText: "\(bookmark.displayTitle), \(WidgetStrings.complicationUnavailable)"
                )
                .widgetAccentable()

            case .noBookmarks:
                ComplicationCircularFallbackContent(
                    routeShortName: nil,
                    systemImage: "bookmark",
                    accessibilityText: WidgetStrings.complicationNoBookmarks
                )
                .widgetAccentable()
            }
        }
    }

    private var rectangularView: some View {
        Group {
            switch state {
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
                    subtitle: WidgetStrings.noDepartures(inNextMinutes: 60),
                    systemImage: nil
                )
                .widgetAccentable()

            case .unavailable(let bookmark):
                ComplicationRectangularFallbackContent(
                    title: bookmark.displayTitle,
                    subtitle: WidgetStrings.complicationUnavailable,
                    systemImage: nil
                )
                .widgetAccentable()

            case .noBookmarks:
                ComplicationRectangularFallbackContent(
                    title: WidgetStrings.complicationNoBookmarks,
                    subtitle: WidgetStrings.complicationNoBookmarksHint,
                    systemImage: "bookmark"
                )
                .widgetAccentable()
            }
        }
    }

    private var inlineView: some View {
        Group {
            switch state {
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
                Text(verbatim: "\(bookmark.displayTitle) · \(WidgetStrings.complicationNoDepartures)")

            case .unavailable(let bookmark):
                Text(verbatim: "\(bookmark.displayTitle) · \(WidgetStrings.complicationUnavailable)")

            case .noBookmarks:
                Text(verbatim: WidgetStrings.complicationNoBookmarks)
            }
        }
    }
}
