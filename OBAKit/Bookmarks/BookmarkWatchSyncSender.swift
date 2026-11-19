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

/// The `WatchSessionBridge` members the sender uses. Tests pass a stand-in so
/// they don't read the live WatchConnectivity session.
public protocol BookmarkWatchSyncBridge: AnyObject {
    var canSendToWatch: Bool { get }
    var lastSentPayload: WatchSyncPayload? { get }
    var lastSentRevision: String? { get }
    func activate()
    func send(payload: WatchSyncPayload) throws
}

extension WatchSessionBridge: BookmarkWatchSyncBridge {}

/// Observes bookmark and region changes in the iOS app and transmits the trimmed
/// `WatchSyncPayload` to paired Apple Watches via `WatchSessionBridge`.
@MainActor
public final class BookmarkWatchSyncSender: NSObject, RegionsServiceDelegate {
    public typealias TransportHandler = @MainActor (WatchSyncPayload) throws -> Void

    private let userDataStore: UserDataStore
    private let regionsService: RegionsService
    private let bridge: any BookmarkWatchSyncBridge
    private let userDefaults: UserDefaults
    private let debounceInterval: Duration
    private let retryDelays: [Duration]
    private let clock: any Clock<Duration>
    private let transport: TransportHandler?

    private var debounceTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var epoch: UUID
    private var sequenceNumber: Int64
    /// The revision `sequenceNumber` was last bumped for.
    private var lastBuiltRevision: String?
    /// The revision last handed to the transport.
    private var lastSentRevision: String?
    private var retryCount = 0

    private static let sequenceNumberKey = "BookmarkWatchSyncSender.sequenceNumber"
    // The key name from before the split, when it held either revision. Read
    // as the built one only, the first sync after upgrading sends even when
    // nothing changed.
    private static let lastBuiltRevisionKey = "BookmarkWatchSyncSender.lastRevision"
    private static let lastSentRevisionKey = "BookmarkWatchSyncSender.lastSentRevision"
    private static let epochFileName = "epoch"

    /// Where the epoch is kept: a directory in Application Support that is
    /// excluded from backups. The sequence counter lives in `UserDefaults`,
    /// which backups do restore, so restoring an older backup rolls the counter
    /// back. The epoch has to change when that happens, or the watch rejects
    /// edits until the counter catches up.
    public static let defaultEpochDirectory: URL? = try? FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: false
    ).appendingPathComponent("WatchSync", isDirectory: true)

    public init(
        userDataStore: UserDataStore,
        regionsService: RegionsService,
        bridge: any BookmarkWatchSyncBridge = WatchSessionBridge.shared,
        userDefaults: UserDefaults = .standard,
        epochDirectory: URL? = BookmarkWatchSyncSender.defaultEpochDirectory,
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

        self.epoch = Self.persistedEpoch(in: epochDirectory)

        let bridgeSeq = bridge.lastSentPayload?.sequenceNumber ?? 0
        let defaultsSeq = Int64(userDefaults.integer(forKey: Self.sequenceNumberKey))
        self.sequenceNumber = max(bridgeSeq, defaultsSeq)
        self.lastBuiltRevision = userDefaults.string(forKey: Self.lastBuiltRevisionKey) ?? bridge.lastSentRevision
        self.lastSentRevision = bridge.lastSentRevision ?? userDefaults.string(forKey: Self.lastSentRevisionKey)
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

        if !force, let current = makePayload(), current.revision == (bridge.lastSentRevision ?? lastSentRevision) {
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
            userDefaults.set(lastSentRevision, forKey: Self.lastSentRevisionKey)
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

    /// The payload to send: bumps and saves the sequence number when the
    /// content changed since the last build.
    public func buildPayload() -> WatchSyncPayload? {
        guard let payload = makePayload() else { return nil }
        guard payload.revision != lastBuiltRevision else { return payload }

        sequenceNumber += 1
        userDefaults.set(sequenceNumber, forKey: Self.sequenceNumberKey)
        lastBuiltRevision = payload.revision
        userDefaults.set(lastBuiltRevision, forKey: Self.lastBuiltRevisionKey)
        return WatchSyncPayload(
            schemaVersion: payload.schemaVersion,
            revision: payload.revision,
            sequenceNumber: sequenceNumber,
            epoch: epoch,
            bookmarks: payload.bookmarks,
            groups: payload.groups,
            region: payload.region
        )
    }

    /// The current bookmarks, groups and region at the current sequence
    /// number. Changes no state, so it's safe for checks.
    private func makePayload() -> WatchSyncPayload? {
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

        return try? WatchSyncPayload(
            sequenceNumber: sequenceNumber,
            epoch: epoch,
            bookmarks: orderedBookmarks,
            groups: groups.map { WatchBookmarkGroup(group: $0) },
            region: regionsService.currentRegion
        )
    }

    /// Reads the epoch from `directory`, or makes and saves a new one. With no
    /// directory, each launch gets a new epoch, which the watch accepts.
    private static func persistedEpoch(in directory: URL?) -> UUID {
        guard var directory else { return UUID() }
        let fileURL = directory.appendingPathComponent(epochFileName, isDirectory: false)

        if let data = try? Data(contentsOf: fileURL),
           let string = String(data: data, encoding: .utf8),
           let epoch = UUID(uuidString: string.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return epoch
        }

        let epoch = UUID()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try directory.setResourceValues(resourceValues)
            try epoch.uuidString.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            Logger.error("BookmarkWatchSyncSender: couldn't save the epoch: \(error.localizedDescription)")
        }
        return epoch
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
