//
//  BookmarkWatchSyncSender.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// Observes bookmark and region changes in the iOS app and transmits the trimmed
/// `WatchSyncPayload` to paired Apple Watches via `WatchSessionBridge`.
@MainActor
public final class BookmarkWatchSyncSender: NSObject, RegionsServiceDelegate {
    public typealias TransportHandler = @MainActor (WatchSyncPayload) throws -> Void

    private let userDataStore: UserDataStore
    private let regionsService: RegionsService
    private let bridge: WatchSessionBridge
    private let debounceInterval: Duration
    private let transport: TransportHandler?

    private var debounceTask: Task<Void, Never>?

    public init(
        userDataStore: UserDataStore,
        regionsService: RegionsService,
        bridge: WatchSessionBridge = .shared,
        debounceInterval: Duration = .milliseconds(1500),
        transport: TransportHandler? = nil
    ) {
        self.userDataStore = userDataStore
        self.regionsService = regionsService
        self.bridge = bridge
        self.debounceInterval = debounceInterval
        self.transport = transport
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dataDidChange),
            name: .bookmarksDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dataDidChange),
            name: .bookmarkGroupsDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionStateDidChange),
            name: .watchSessionStateDidChange,
            object: nil
        )

        regionsService.addDelegate(self)
        bridge.activate()

        if bridge.canSendToWatch {
            syncNow(force: true)
        }
    }

    @objc private nonisolated func dataDidChange() {
        Task { @MainActor in
            self.scheduleSync()
        }
    }

    @objc private nonisolated func sessionStateDidChange() {
        Task { @MainActor in
            guard self.bridge.canSendToWatch else { return }
            self.syncNow(force: true)
        }
    }

    public func scheduleSync(force: Bool = false) {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.debounceInterval)
            guard !Task.isCancelled else { return }
            self.syncNow(force: force)
        }
    }

    public func syncNow(force: Bool = false) {
        guard let payload = buildPayload() else { return }

        // Skip sending if revision matches last sent, unless forced (e.g. watch activation or watch app installed)
        if !force, let lastRevision = bridge.lastSentRevision, lastRevision == payload.revision {
            return
        }

        do {
            if let transport {
                try transport(payload)
            } else {
                try bridge.send(payload: payload)
            }
        } catch {
            Logger.error("BookmarkWatchSyncSender: send failed: \(error.localizedDescription)")
        }
    }

    public func buildPayload() -> WatchSyncPayload? {
        // Flatten bookmarks in display order:
        // groups by sortOrder, then bookmarks in each group by sortOrder, ungrouped last.
        let groups = userDataStore.bookmarkGroups.sorted { $0.sortOrder < $1.sortOrder }
        var orderedBookmarks: [WatchBookmark] = []

        for group in groups {
            let groupBookmarks = userDataStore.bookmarksInGroup(group)
            orderedBookmarks.append(contentsOf: groupBookmarks.map { WatchBookmark(bookmark: $0) })
        }

        let ungrouped = userDataStore.bookmarksInGroup(nil)
        orderedBookmarks.append(contentsOf: ungrouped.map { WatchBookmark(bookmark: $0) })

        let watchGroups = groups.map { WatchBookmarkGroup(group: $0) }
        let currentRegion = regionsService.currentRegion

        return try? WatchSyncPayload(
            bookmarks: orderedBookmarks,
            groups: watchGroups,
            region: currentRegion
        )
    }

    // MARK: - RegionsServiceDelegate

    public func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        scheduleSync()
    }

    public func regionsService(_ service: RegionsService, updatedRegionsList regions: [Region]) {
        scheduleSync()
    }

    public func regionsService(_ service: RegionsService, updatedCustomRegions regions: [Region]) {
        scheduleSync()
    }
}
