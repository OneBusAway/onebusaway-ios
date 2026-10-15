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
                text: OBALoc("arrivals.no_service", value: "No transit region selected.", comment: "Arrivals cannot load without a region"),
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

    private var bookmark: WatchBookmark {
        bookmarkArrival.bookmark
    }

    private var arrival: ArrivalDeparture? {
        bookmarkArrival.nextArrival
    }

    private var routeColor: Color {
        if let arrival, let route = arrival.route {
            return Color(uiColor: route.color ?? ThemeColors.shared.brand)
        }
        return Color(uiColor: ThemeColors.shared.brand)
    }

    private var routeTextColor: Color? {
        arrival?.route?.textColor.map { Color(uiColor: $0) }
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
            }
            Spacer(minLength: 4)
            if let arrival {
                CountdownView(
                    departure: arrival.arrivalDepartureDate,
                    isRealTime: arrival.predicted,
                    color: countdownColor,
                    emphasized: false
                )
            }
        }
    }
}
