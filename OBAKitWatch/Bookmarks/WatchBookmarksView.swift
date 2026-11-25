//
//  WatchBookmarksView.swift
//  OBAKitWatch
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

public struct WatchBookmarksView: View {
    let model: WatchBookmarksModel
    @Environment(WatchAppHost.self) private var host

    public init(model: WatchBookmarksModel) {
        self.model = model
    }

    public var body: some View {
        content
            .navigationTitle(OBALoc("bookmarks.title", value: "Bookmarks", comment: "Bookmarks navigation title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.refresh()
                    } label: {
                        Label(Strings.refresh, systemImage: "arrow.clockwise")
                    }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView(OBALoc("bookmarks.loading", value: "Loading bookmarks…", comment: "Loading state while bookmark arrivals fetch"))
        case .empty:
            MessageView(
                text: OBALoc("bookmarks.empty", value: "No bookmarks yet. Add bookmarks on your iPhone to see them here.", comment: "Empty state when no bookmarks exist"),
                systemImage: "bookmark"
            )
        case .noRegion:
            MessageView(
                text: Strings.noTransitRegion,
                systemImage: "map"
            )
        case .loaded(let sections):
            List {
                ForEach(sections) { section in
                    if section.title.isEmpty {
                        ForEach(section.bookmarks) { bookmarkArrival in
                            NavigationLink(value: bookmarkArrival.bookmark.stop) {
                                WatchBookmarkRow(bookmarkArrival: bookmarkArrival, formatters: host.formatters)
                            }
                        }
                    } else {
                        Section(section.title) {
                            ForEach(section.bookmarks) { bookmarkArrival in
                                NavigationLink(value: bookmarkArrival.bookmark.stop) {
                                    WatchBookmarkRow(bookmarkArrival: bookmarkArrival, formatters: host.formatters)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct WatchBookmarkRow: View {
    let bookmarkArrival: WatchBookmarkArrival
    let formatters: Formatters

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    private var bookmark: WatchBookmark {
        bookmarkArrival.bookmark
    }

    private var arrival: ArrivalDeparture? {
        bookmarkArrival.nextArrival
    }

    /// Offline, once the saved departures have left.
    private var scheduledDeparture: ScheduledDeparture? {
        bookmarkArrival.nextScheduledDeparture
    }

    private var route: Route? {
        arrival?.route ?? scheduledDeparture?.route
    }

    private var routeColor: Color {
        Color(uiColor: route?.color ?? ThemeColors.shared.brand)
    }

    private var routeTextColor: Color? {
        route?.textColor.map { Color(uiColor: $0) }
    }

    private var countdownColor: Color {
        guard let arrival else { return Color.secondary }
        return Color(uiColor: formatters.colorForScheduleStatus(arrival.scheduleStatus))
    }

    private var routeShortName: String {
        bookmark.routeShortName ?? ""
    }

    private var titleText: String {
        if bookmark.isTripBookmark {
            return bookmark.tripHeadsign ?? bookmark.name
        } else {
            return bookmark.name
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if !routeShortName.isEmpty {
                RouteBadgeView(
                    routeShortName: routeShortName,
                    routeColor: routeColor,
                    routeTextColor: routeTextColor,
                    size: 32
                )
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(titleText)
                    .font(.caption)
                    .lineLimit(2)
                Text(bookmark.stopName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let savedText {
                    // Not truncated: the save time is at the end.
                    Text(savedText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            if let arrival {
                // A single-child stack lays out exactly as the bare countdown,
                // so the row is unchanged unless the glyph is drawn.
                HStack(spacing: 2) {
                    // Schedule-only countdowns already carry a clock glyph.
                    if differentiateWithoutColor, arrival.predicted, bookmarkArrival.savedAt == nil {
                        Image(systemName: arrival.scheduleStatus.differentiateWithoutColorGlyphName(isRealTime: true))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(countdownColor)
                            .accessibilityHidden(true)
                    }
                    CountdownView(
                        departure: arrival.arrivalDepartureDate,
                        // A saved prediction is no longer live.
                        isRealTime: arrival.predicted && bookmarkArrival.savedAt == nil,
                        color: countdownColor,
                        emphasized: false
                    )
                }
            } else if let scheduledDeparture {
                // A timetable time has no prediction: grey, with the clock glyph.
                CountdownView(departure: scheduledDeparture.date, isRealTime: false, color: .secondary, emphasized: false)
            }
        }
        // The route badge and countdown hide themselves from VoiceOver, so the
        // row speaks for them, as `ArrivalRow` does. The enclosing
        // NavigationLink keeps the button trait.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        // The countdown's color is its only adherence cue; say it. With no
        // arrival there is no countdown, so no value either.
        .accessibilityValue(arrival.map { formatters.deviationLabel(for: $0) } ?? "")
        .accessibilityAddTraits(arrival == nil && scheduledDeparture == nil ? [] : .updatesFrequently)
    }

    /// "Offline, saved 8:47 PM" while the departure shown is a saved one, or
    /// "Offline, scheduled times" once it comes from the saved timetable, as
    /// the phone's bookmark cards say. `nil` while live.
    private var savedText: String? {
        guard let savedAt = bookmarkArrival.savedAt else { return nil }
        if arrival == nil, scheduledDeparture != nil {
            return OBALoc("bookmarks.offline_timetable", value: "Offline, scheduled times", comment: "Shown on a bookmark row when the watch is offline, the departures it saved have all left, and the time shown comes from the stop's saved timetable instead.")
        }
        let format = OBALoc("bookmarks.offline_saved_fmt", value: "Offline, saved %@", comment: "Shown on a bookmark row when the watch is offline and the departure shown is the last one it saved. The placeholder is the time it was saved, e.g. 'Offline, saved 8:42 AM'.")
        return String(format: format, savedAtString(savedAt))
    }

    /// The save time, with the date in front when it wasn't today, so
    /// "8:42 AM" can't be mistaken for this morning.
    private func savedAtString(_ savedAt: Date) -> String {
        var calendar = Calendar.current
        calendar.timeZone = formatters.timeFormatter.timeZone
        if calendar.isDateInToday(savedAt) {
            return formatters.timeFormatter.string(from: savedAt)
        }
        let formatter = DateFormatter()
        formatter.locale = formatters.timeFormatter.locale
        formatter.timeZone = formatters.timeFormatter.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: savedAt)
    }

    /// Route and title, stop name, then time until the next arrival when there
    /// is one — the same order the row draws them in.
    private var accessibilityLabel: String {
        var clauses: [String] = []
        if !routeShortName.isEmpty, bookmark.isTripBookmark, let headsign = bookmark.tripHeadsign {
            clauses.append(RouteDirectionBadge.accessibilityLabel(routeShortName: routeShortName, headsign: headsign))
        } else {
            clauses.append(contentsOf: [routeShortName, titleText].filter { !$0.isEmpty })
        }
        if !bookmark.stopName.isEmpty {
            clauses.append(bookmark.stopName)
        }
        if let arrival {
            clauses.append(formatters.formattedTime(until: arrival))
        } else if let scheduledDeparture {
            let minutes = scheduledDeparture.minutes
            clauses.append(formatters.formattedTimeUntilArrivalDeparture(arrivalDepartureMinutes: minutes, temporalState: minutes == 0 ? .present : .future))
        }
        if let savedText {
            clauses.append(savedText)
        }
        return clauses.joined(separator: ", ")
    }
}
