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
    private let userDefaults: UserDefaults
    private let debounceInterval: Duration
    private let retryDelays: [Duration]
    private let clock: any Clock<Duration>
    private let transport: TransportHandler?

    private var debounceTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var epoch: UUID
    private var sequenceNumber: Int64
    private var lastRevision: String?
    private var lastSentRevision: String?
    private var retryCount = 0

    private static let epochKey = "BookmarkWatchSyncSender.epoch"
    private static let sequenceNumberKey = "BookmarkWatchSyncSender.sequenceNumber"
    private static let lastRevisionKey = "BookmarkWatchSyncSender.lastRevision"

    public init(
        userDataStore: UserDataStore,
        regionsService: RegionsService,
        bridge: WatchSessionBridge = .shared,
        userDefaults: UserDefaults = .standard,
        debounceInterval: Duration = .milliseconds(1500),
        retryDelays: [Duration] = [.milliseconds(500), .milliseconds(1000), .milliseconds(2000)],
        clock: any Clock<Duration> = ContinuousClock(),
        transport: TransportHandler? = nil
    ) {
        self.userDataStore = userDataStore
        self.regionsService = regionsService
        self.bridge = bridge
        self.userDefaults = userDefaults
        self.debounceInterval = debounceInterval
        self.retryDelays = retryDelays
        self.clock = clock
        self.transport = transport

        if let storedEpochString = userDefaults.string(forKey: Self.epochKey),
           let storedEpoch = UUID(uuidString: storedEpochString) {
            self.epoch = storedEpoch
        } else if let bridgeEpoch = bridge.lastSentPayload?.epoch {
            self.epoch = bridgeEpoch
            userDefaults.set(bridgeEpoch.uuidString, forKey: Self.epochKey)
        } else {
            let newEpoch = UUID()
            self.epoch = newEpoch
            userDefaults.set(newEpoch.uuidString, forKey: Self.epochKey)
        }

        let bridgeSeq = bridge.lastSentPayload?.sequenceNumber ?? 0
        let defaultsSeq = Int64(userDefaults.integer(forKey: Self.sequenceNumberKey))
        self.sequenceNumber = max(bridgeSeq, defaultsSeq)
        self.lastRevision = bridge.lastSentRevision ?? userDefaults.string(forKey: Self.lastRevisionKey)
        self.lastSentRevision = bridge.lastSentRevision ?? userDefaults.string(forKey: Self.lastRevisionKey)
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dataDidChange),
            name: .bookmarksDidChange,
            object: userDataStore
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dataDidChange),
            name: .bookmarkGroupsDidChange,
            object: userDataStore
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionStateDidChange),
            name: .watchSessionStateDidChange,
            object: bridge
        )

        regionsService.addDelegate(self)
        bridge.activate()

        if bridge.canSendToWatch {
            syncNow(force: true)
        }
    }

    deinit {
        debounceTask?.cancel()
        retryTask?.cancel()
    }

    @objc private nonisolated func dataDidChange() {
        Task { @MainActor in
            self.scheduleSync()
        }
    }

    @objc private nonisolated func sessionStateDidChange() {
        Task { @MainActor in
            guard self.bridge.canSendToWatch else { return }
            self.retryTask?.cancel()
            self.retryTask = nil
            self.retryCount = 0
            self.syncNow(force: true)
        }
    }

    public func scheduleSync(force: Bool = false) {
        guard retryTask == nil else { return }

        if !force, let current = buildPayload(), current.revision == (bridge.lastSentRevision ?? lastSentRevision) {
            return
        }

        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self, clock] in
            guard let self else { return }
            try? await clock.sleep(for: self.debounceInterval)
            guard !Task.isCancelled else { return }
            self.syncNow(force: force)
        }
    }

    /// Performs an explicit, non-debounced sync now, cancelling any pending debounces or retries.
    public func syncExplicitly() {
        debounceTask?.cancel()
        debounceTask = nil
        retryTask?.cancel()
        retryTask = nil
        retryCount = 0
        syncNow(force: true)
    }

    public func syncNow(force: Bool = false) {
        guard let payload = buildPayload() else { return }

        // Skip sending if revision matches last sent, unless forced (e.g. watch activation or watch app installed)
        let effectiveLastSent = bridge.lastSentRevision ?? lastSentRevision
        if !force, let effectiveLastSent, effectiveLastSent == payload.revision {
            return
        }

        do {
            if let transport {
                try transport(payload)
            } else {
                try bridge.send(payload: payload)
            }
            lastSentRevision = payload.revision
            userDefaults.set(lastSentRevision, forKey: Self.lastRevisionKey)
            retryCount = 0
            retryTask?.cancel()
            retryTask = nil
        } catch {
            Logger.error("BookmarkWatchSyncSender: send failed: \(error.localizedDescription)")
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        guard retryCount < retryDelays.count else {
            retryTask = nil
            retryCount = 0
            return
        }
        let delay = retryDelays[retryCount]
        retryCount += 1
        retryTask?.cancel()
        retryTask = Task { @MainActor [weak self, clock] in
            guard let self else { return }
            try? await clock.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self.syncNow(force: true)
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

        guard let payload = try? WatchSyncPayload(
            sequenceNumber: sequenceNumber,
            epoch: epoch,
            bookmarks: orderedBookmarks,
            groups: watchGroups,
            region: currentRegion
        ) else { return nil }

        if payload.revision != lastRevision {
            sequenceNumber += 1
            userDefaults.set(sequenceNumber, forKey: Self.sequenceNumberKey)
            lastRevision = payload.revision
            userDefaults.set(lastRevision, forKey: Self.lastRevisionKey)
            return try? WatchSyncPayload(
                sequenceNumber: sequenceNumber,
                epoch: epoch,
                bookmarks: orderedBookmarks,
                groups: watchGroups,
                region: currentRegion
            )
        }

        return payload
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
