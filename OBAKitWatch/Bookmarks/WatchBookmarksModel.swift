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

    public var id: UUID { bookmark.id }

    public init(bookmark: WatchBookmark, nextArrival: ArrivalDeparture? = nil) {
        self.bookmark = bookmark
        self.nextArrival = nextArrival
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

    public init(host: WatchAppHost, loader: BookmarkArrivalsLoader = BookmarkArrivalsLoader()) {
        self.host = host
        self.loader = loader
        self.phase = .loading
    }

    public init(phase: Phase) {
        self.host = nil
        self.loader = BookmarkArrivalsLoader()
        self.phase = phase
    }

    public func refresh() {
        guard let host else { return }
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.loadBookmarks(from: host)
        }
    }

    private func loadBookmarks(from host: WatchAppHost) async {
        let bookmarks = host.bookmarkStore.bookmarks
        guard !bookmarks.isEmpty else {
            self.phase = .empty
            return
        }

        guard let apiService = host.apiService else {
            self.phase = .noRegion
            return
        }

        self.phase = .loading

        let departures = await loader.departuresByWatchBookmark(for: bookmarks, using: apiService)

        var sections: [WatchBookmarkSection] = []
        let groups = host.bookmarkStore.groups

        for group in groups {
            let groupBookmarks = bookmarks.filter { $0.groupID == group.id }
            guard !groupBookmarks.isEmpty else { continue }
            let bookmarkArrivals = groupBookmarks.map { bm in
                WatchBookmarkArrival(bookmark: bm, nextArrival: departures[bm.id]?.first)
            }
            sections.append(WatchBookmarkSection(id: group.id, title: group.name, bookmarks: bookmarkArrivals))
        }

        let ungrouped = bookmarks.filter { $0.groupID == nil }
        if !ungrouped.isEmpty {
            let bookmarkArrivals = ungrouped.map { bm in
                WatchBookmarkArrival(bookmark: bm, nextArrival: departures[bm.id]?.first)
            }
            let title = sections.isEmpty ? "" : OBALoc("bookmarks.title", value: "Bookmarks", comment: "Section title for ungrouped bookmarks")
            let sectionID = UUID(uuidString: "00000000-0000-0000-0000-000000000000") ?? UUID()
            sections.append(WatchBookmarkSection(id: sectionID, title: title, bookmarks: bookmarkArrivals))
        }

        self.phase = sections.isEmpty ? .empty : .loaded(sections)
    }
}
