//
//  WatchBookmarksModel.swift
//  OBAKitWatch
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Observation
import OBAKitCore

public struct WatchBookmarkArrival: Identifiable, Equatable {
    public let bookmark: WatchBookmark
    public let nextArrival: ArrivalDeparture?

    /// Offline, once the saved departures have left: the next one in the
    /// stop's saved timetable.
    public let nextScheduledDeparture: ScheduledDeparture?

    /// When the departure shown was saved, while the watch can't reach the
    /// server; `nil` while it's live.
    public let savedAt: Date?

    public var id: UUID { bookmark.id }

    public init(bookmark: WatchBookmark, nextArrival: ArrivalDeparture? = nil, nextScheduledDeparture: ScheduledDeparture? = nil, savedAt: Date? = nil) {
        self.bookmark = bookmark
        self.nextArrival = nextArrival
        self.nextScheduledDeparture = nextScheduledDeparture
        self.savedAt = savedAt
    }
}

public struct WatchBookmarkSection: Identifiable, Equatable {
    public let id: UUID
    public let title: String
    public let bookmarks: [WatchBookmarkArrival]

    public init(id: UUID, title: String, bookmarks: [WatchBookmarkArrival]) {
        self.id = id
        self.title = title
        self.bookmarks = bookmarks
    }
}

/// Drives the Bookmarks tab on Apple Watch: loads upcoming departures for synced bookmarks.
@MainActor
@Observable
public final class WatchBookmarksModel {
    public enum Phase: Equatable {
        case loading
        case empty
        case loaded([WatchBookmarkSection])
        case noRegion
    }

    public private(set) var phase: Phase

    @ObservationIgnored private let host: WatchAppHost?
    @ObservationIgnored private let loader: BookmarkArrivalsLoader
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var autoRefreshTask: Task<Void, Never>?

    /// The default loader saves each stop's departures on the watch, and shows
    /// them when the watch can't reach the server.
    public init(host: WatchAppHost, loader: BookmarkArrivalsLoader = BookmarkArrivalsLoader(savedArrivals: .appDefault)) {
        self.host = host
        self.loader = loader
        self.phase = .loading
    }

    public init(phase: Phase) {
        self.host = nil
        self.loader = BookmarkArrivalsLoader()
        self.phase = phase
    }

    deinit {
        refreshTask?.cancel()
        autoRefreshTask?.cancel()
    }

    public func cancel() {
        refreshTask?.cancel()
        autoRefreshTask?.cancel()
    }

    public func refresh() {
        guard let host else { return }
        refreshTask?.cancel()
        autoRefreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.loadBookmarks(from: host)
        }
    }

    private func loadBookmarks(from host: WatchAppHost) async {
        let allBookmarks = host.bookmarkStore.bookmarks
        guard !allBookmarks.isEmpty else {
            self.phase = .empty
            return
        }

        guard let apiService = host.apiService else {
            self.phase = .noRegion
            return
        }

        let bookmarks: [WatchBookmark]
        if let currentRegionID = host.currentRegion?.regionIdentifier {
            bookmarks = allBookmarks.filter { Int($0.regionIdentifier) == currentRegionID }
        } else {
            bookmarks = allBookmarks
        }

        guard !bookmarks.isEmpty else {
            self.phase = .empty
            return
        }

        if case .loaded = self.phase {
            // Keep existing sections visible during refresh to avoid a spinner flash.
        } else {
            self.phase = .loading
        }

        let groups = host.bookmarkStore.groups
        for await departures in loader.nextDeparturesByWatchBookmark(for: bookmarks, using: apiService) {
            guard !Task.isCancelled else { return }
            self.publishSections(bookmarks: bookmarks, groups: groups, departures: departures)
        }
    }

    /// Rebuilds the tab's sections from the departures and schedules the next
    /// refresh from them. Runs once every stop has reported, while the day's
    /// timetables may still be downloading.
    private func publishSections(bookmarks: [WatchBookmark], groups: [WatchBookmarkGroup], departures: [UUID: WatchBookmarkDeparture]) {
        var sections: [WatchBookmarkSection] = []
        let now = Date()

        for group in groups {
            let groupBookmarks = bookmarks.filter { $0.groupID == group.id }
            guard !groupBookmarks.isEmpty else { continue }
            let bookmarkArrivals = Self.bookmarkArrivals(for: groupBookmarks, departures: departures)
            sections.append(WatchBookmarkSection(id: group.id, title: group.name, bookmarks: bookmarkArrivals))
        }

        let ungrouped = bookmarks.filter { $0.groupID == nil }
        if !ungrouped.isEmpty {
            let bookmarkArrivals = Self.bookmarkArrivals(for: ungrouped, departures: departures)
            let title = sections.isEmpty ? "" : OBALoc("bookmarks.title", value: "Bookmarks", comment: "Section title for ungrouped bookmarks")
            let sectionID = UUID(uuidString: "00000000-0000-0000-0000-000000000000") ?? UUID()
            sections.append(WatchBookmarkSection(id: sectionID, title: title, bookmarks: bookmarkArrivals))
        }

        self.phase = sections.isEmpty ? .empty : .loaded(sections)
        let upcomingDepartureDates = sections.flatMap(\.bookmarks).compactMap { $0.nextArrival?.arrivalDepartureDate ?? $0.nextScheduledDeparture?.date }
        let nextRefreshDate = upcomingDepartureDates.min() ?? (sections.isEmpty ? nil : now.addingTimeInterval(60.0))
        scheduleAutoRefresh(at: nextRefreshDate)
    }

    /// Pairs each bookmark with its next upcoming departure.
    private static func bookmarkArrivals(for bookmarks: [WatchBookmark], departures: [UUID: WatchBookmarkDeparture]) -> [WatchBookmarkArrival] {
        bookmarks.map { bookmark in
            let departure = departures[bookmark.id]
            return WatchBookmarkArrival(
                bookmark: bookmark,
                nextArrival: departure?.arrival,
                nextScheduledDeparture: departure?.scheduledDeparture,
                savedAt: departure?.savedAt
            )
        }
    }

    private func scheduleAutoRefresh(at earliestDate: Date?) {
        autoRefreshTask?.cancel()
        guard let earliestDate else { return }
        let delay = max(1.0, earliestDate.timeIntervalSinceNow + 1.0)
        autoRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}
