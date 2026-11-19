//
//  BookmarkWatchSyncSenderTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class BookmarkWatchSyncSenderTests: OBATestCase {

    private var queue: OperationQueue!
    /// Each test gets its own epoch file, so none reads another's epoch.
    private let epochDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("BookmarkWatchSyncSenderTests-\(UUID().uuidString)", isDirectory: true)

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
        try? FileManager.default.removeItem(at: epochDirectory)
    }

    /// Stands in for `WatchSessionBridge.shared`, whose starting epoch and
    /// sequence number come from the live WatchConnectivity session.
    private final class FakeWatchSyncBridge: BookmarkWatchSyncBridge {
        var canSendToWatch = false
        var lastSentPayload: WatchSyncPayload?
        var lastSentRevision: String? { lastSentPayload?.revision }
        func activate() {}
        func send(payload: WatchSyncPayload) throws {
            lastSentPayload = payload
        }
    }

    @MainActor
    private func makeUserDefaults(suitePrefix: String = "TestSender") throws -> (UserDefaults, String) {
        let suiteName = "\(suitePrefix)_\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return (defaults, suiteName)
    }

    @MainActor
    private func makeBookmark(application: Application, name: String = "Test Bookmark") throws -> Bookmark {
        let stops = try Fixtures.loadSomeStops()
        let stop = try #require(stops.first)
        return Bookmark(
            name: name,
            regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier,
            stop: stop
        )
    }

    @Test @MainActor func `Payload construction orders bookmarks correctly`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let (defaults, suiteName) = try makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let sender = BookmarkWatchSyncSender(
            userDataStore: application.userDataStore,
            regionsService: application.regionsService,
            bridge: FakeWatchSyncBridge(),
            userDefaults: defaults,
            epochDirectory: epochDirectory,
            debounceInterval: .milliseconds(50)
        )

        let groupA = BookmarkGroup(name: "Group A", sortOrder: 1)
        let groupB = BookmarkGroup(name: "Group B", sortOrder: 0)

        application.userDataStore.upsert(bookmarkGroup: groupA)
        application.userDataStore.upsert(bookmarkGroup: groupB)

        let b1 = try makeBookmark(application: application, name: "Bookmark 1")
        let b2 = try makeBookmark(application: application, name: "Bookmark 2")
        let bUngrouped = try makeBookmark(application: application, name: "Ungrouped")

        application.userDataStore.add(b1, to: groupA)
        application.userDataStore.add(b2, to: groupB)
        application.userDataStore.add(bUngrouped, to: nil)

        let payload = try #require(sender.buildPayload())

        #expect(payload.groups.map(\.name) == ["Group B", "Group A"])
        #expect(payload.bookmarks.map(\.name) == ["Bookmark 2", "Bookmark 1", "Ungrouped"])
    }

    @Test @MainActor func `Debounce coalesces rapid changes`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let clock = TestClock()
        let (defaults, suiteName) = try makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var sendCount = 0
        let sender = BookmarkWatchSyncSender(
            userDataStore: application.userDataStore,
            regionsService: application.regionsService,
            bridge: FakeWatchSyncBridge(),
            userDefaults: defaults,
            epochDirectory: epochDirectory,
            debounceInterval: .milliseconds(100),
            clock: clock,
            transport: { _ in
                sendCount += 1
            }
        )

        NotificationCenter.default.post(name: .bookmarksDidChange, object: application.userDataStore)
        NotificationCenter.default.post(name: .bookmarkGroupsDidChange, object: application.userDataStore)
        NotificationCenter.default.post(name: .bookmarksDidChange, object: application.userDataStore)

        await poll(until: { clock.sleeperCount == 1 })
        clock.advance(by: .milliseconds(100))

        await poll(until: { sendCount == 1 })
        #expect(sendCount == 1)
        #expect(sender.buildPayload() != nil)
    }

    @Test @MainActor func `Explicit sync transmits immediately without waiting for debounce`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let (defaults, suiteName) = try makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var sendCount = 0
        let sender = BookmarkWatchSyncSender(
            userDataStore: application.userDataStore,
            regionsService: application.regionsService,
            bridge: FakeWatchSyncBridge(),
            userDefaults: defaults,
            epochDirectory: epochDirectory,
            debounceInterval: .seconds(60),
            transport: { _ in
                sendCount += 1
            }
        )

        let bookmark = try makeBookmark(application: application, name: "Immediate Sync")
        application.userDataStore.add(bookmark, to: nil)

        // syncExplicitly fires right away without waiting 60s
        sender.syncExplicitly()

        #expect(sendCount == 1)
    }

    @Test @MainActor func `Failed transport triggers bounded retry and recovers`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let clock = TestClock()
        let (defaults, suiteName) = try makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        struct MockTransportError: Error {}

        var attempts = 0
        var successfulSends = 0

        let sender = BookmarkWatchSyncSender(
            userDataStore: application.userDataStore,
            regionsService: application.regionsService,
            bridge: FakeWatchSyncBridge(),
            userDefaults: defaults,
            epochDirectory: epochDirectory,
            debounceInterval: .milliseconds(50),
            retryDelays: [.milliseconds(30), .milliseconds(50)],
            clock: clock,
            transport: { _ in
                attempts += 1
                if attempts < 2 {
                    throw MockTransportError()
                }
                successfulSends += 1
            }
        )

        let bookmark = try makeBookmark(application: application, name: "Retry Stop")
        application.userDataStore.add(bookmark, to: nil)

        sender.syncExplicitly()
        #expect(attempts == 1)
        #expect(successfulSends == 0)

        // Wait for retry sleep and advance clock
        await poll(until: { clock.sleeperCount == 1 })
        clock.advance(by: .milliseconds(30))

        await poll(until: { successfulSends == 1 })
        #expect(attempts == 2)
        #expect(successfulSends == 1)
    }

    @Test @MainActor func `Sender restart preserves sequence counter across launches`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let suiteName = "TestSenderRestart_\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var firstSentPayload: WatchSyncPayload?
        let sender1 = BookmarkWatchSyncSender(
            userDataStore: application.userDataStore,
            regionsService: application.regionsService,
            bridge: FakeWatchSyncBridge(),
            userDefaults: defaults,
            epochDirectory: epochDirectory,
            transport: { firstSentPayload = $0 }
        )

        let b1 = try makeBookmark(application: application, name: "Stop 1")
        application.userDataStore.add(b1, to: nil)
        sender1.syncExplicitly()

        let p1 = try #require(firstSentPayload)
        #expect(p1.sequenceNumber == 1)

        // Simulate app relaunch: instantiate a fresh sender with the same persisted state
        var secondSentPayload: WatchSyncPayload?
        let sender2 = BookmarkWatchSyncSender(
            userDataStore: application.userDataStore,
            regionsService: application.regionsService,
            bridge: FakeWatchSyncBridge(),
            userDefaults: defaults,
            epochDirectory: epochDirectory,
            transport: { secondSentPayload = $0 }
        )

        let b2 = try makeBookmark(application: application, name: "Stop 2")
        application.userDataStore.add(b2, to: nil)
        sender2.syncExplicitly()

        let p2 = try #require(secondSentPayload)
        #expect(p2.sequenceNumber > p1.sequenceNumber)
        #expect(p2.sequenceNumber == 2)
        #expect(p2.epoch == p1.epoch)
    }

    @Test @MainActor func `Subsequent edits after retry exhaustion send fresh snapshot`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let clock = TestClock()
        let (defaults, suiteName) = try makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        struct MockTransportError: Error {}

        final class TestState: @unchecked Sendable {
            var shouldFail = true
            var attempts = 0
            var lastSent: WatchSyncPayload?
        }
        let state = TestState()

        let b1 = try makeBookmark(application: application, name: "Old Snapshot")
        application.userDataStore.add(b1, to: nil)

        let sender = BookmarkWatchSyncSender(
            userDataStore: application.userDataStore,
            regionsService: application.regionsService,
            bridge: FakeWatchSyncBridge(),
            userDefaults: defaults,
            epochDirectory: epochDirectory,
            debounceInterval: .milliseconds(50),
            retryDelays: [.milliseconds(20)],
            clock: clock,
            transport: { payload in
                state.attempts += 1
                if state.shouldFail {
                    throw MockTransportError()
                }
                state.lastSent = payload
            }
        )

        // Initial send fails
        sender.syncExplicitly()
        #expect(state.attempts == 1)

        // Wait for retry sleep and advance clock; retry fails too
        await poll(until: { clock.sleeperCount == 1 })
        clock.advance(by: .milliseconds(20))
        await poll(until: { state.attempts == 2 })

        // Retries now exhausted. Transport recovers.
        state.shouldFail = false

        // User creates new bookmark without calling syncExplicitly:
        let b2 = try makeBookmark(application: application, name: "New Snapshot")
        application.userDataStore.add(b2, to: nil)

        // Advance debounce interval for normal scheduleSync path
        await poll(until: { clock.sleeperCount == 1 })
        clock.advance(by: .milliseconds(50))
        await poll(until: { state.attempts == 3 })

        let sent = try #require(state.lastSent)
        #expect(sent.bookmarks.map(\.name).contains("New Snapshot"))
        #expect(sent.bookmarks.count == 2)
    }

    @Test @MainActor func `Empty bookmarks produces valid payload and transmits`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let (defaults, suiteName) = try makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var sentPayload: WatchSyncPayload?
        let sender = BookmarkWatchSyncSender(
            userDataStore: application.userDataStore,
            regionsService: application.regionsService,
            bridge: FakeWatchSyncBridge(),
            userDefaults: defaults,
            epochDirectory: epochDirectory,
            debounceInterval: .milliseconds(50),
            transport: { payload in
                sentPayload = payload
            }
        )

        sender.syncExplicitly()

        let payload = try #require(sentPayload)
        #expect(payload.bookmarks.isEmpty)
        #expect(payload.groups.isEmpty)
    }

    @Test @MainActor func `Epoch is kept in a directory excluded from backups`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let (defaults, suiteName) = try makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var sent: WatchSyncPayload?
        let sender = BookmarkWatchSyncSender(
            userDataStore: application.userDataStore,
            regionsService: application.regionsService,
            bridge: FakeWatchSyncBridge(),
            userDefaults: defaults,
            epochDirectory: epochDirectory,
            transport: { sent = $0 }
        )
        sender.syncExplicitly()

        let epoch = try #require(sent?.epoch)
        let stored = try String(contentsOf: epochDirectory.appendingPathComponent("epoch"), encoding: .utf8)
        #expect(stored == epoch.uuidString)
        let resourceValues = try epochDirectory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(resourceValues.isExcludedFromBackup == true)
        #expect(defaults.dictionaryRepresentation().values.contains { ($0 as? String) == epoch.uuidString } == false)
    }

    @Test @MainActor func `Restoring an older backup starts a new epoch`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let (defaults, suiteName) = try makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var sent: [WatchSyncPayload] = []
        let sender1 = BookmarkWatchSyncSender(
            userDataStore: application.userDataStore,
            regionsService: application.regionsService,
            bridge: FakeWatchSyncBridge(),
            userDefaults: defaults,
            epochDirectory: epochDirectory,
            transport: { sent.append($0) }
        )
        sender1.syncExplicitly()

        // A backup taken now holds sequence number 1.
        let backup = try #require(defaults.persistentDomain(forName: suiteName))

        let bookmark = try makeBookmark(application: application, name: "After Backup")
        application.userDataStore.add(bookmark, to: nil)
        sender1.syncExplicitly()
        #expect(sent.last?.sequenceNumber == 2)

        // Restore: the bookmarks and UserDefaults roll back, but the epoch
        // directory isn't in the backup, so it comes back empty.
        application.userDataStore.delete(bookmark: bookmark)
        defaults.setPersistentDomain(backup, forName: suiteName)
        try FileManager.default.removeItem(at: epochDirectory)

        let sender2 = BookmarkWatchSyncSender(
            userDataStore: application.userDataStore,
            regionsService: application.regionsService,
            bridge: FakeWatchSyncBridge(),
            userDefaults: defaults,
            epochDirectory: epochDirectory,
            transport: { sent.append($0) }
        )
        sender2.syncExplicitly()

        let restored = try #require(sent.last)
        #expect(restored.sequenceNumber == 1)
        #expect(restored.epoch != sent.first?.epoch)

        // The watch, still holding sequence 2 from the old epoch, applies the
        // restored phone's lower sequence number.
        let store = WatchBookmarkStore(userDefaults: defaults)
        #expect(store.update(payload: sent[1]))
        #expect(store.update(payload: restored))
    }

    @Test @MainActor func `A built but unsent revision is sent after a relaunch`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let clock = TestClock()
        let (defaults, suiteName) = try makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let sender1 = BookmarkWatchSyncSender(
            userDataStore: application.userDataStore,
            regionsService: application.regionsService,
            bridge: FakeWatchSyncBridge(),
            userDefaults: defaults,
            epochDirectory: epochDirectory,
            // Never advanced, so the debounce from adding the bookmark below never fires.
            clock: TestClock(),
            transport: { _ in Issue.record("sender1 should not send") }
        )
        application.userDataStore.add(try makeBookmark(application: application, name: "Built Only"), to: nil)
        let built = try #require(sender1.buildPayload())

        // Relaunch with no application context on the session.
        var sent: WatchSyncPayload?
        let sender2 = BookmarkWatchSyncSender(
            userDataStore: application.userDataStore,
            regionsService: application.regionsService,
            bridge: FakeWatchSyncBridge(),
            userDefaults: defaults,
            epochDirectory: epochDirectory,
            debounceInterval: .milliseconds(50),
            clock: clock,
            transport: { sent = $0 }
        )
        sender2.scheduleSync()

        await poll(until: { clock.sleeperCount == 1 })
        clock.advance(by: .milliseconds(50))
        await poll(until: { sent != nil })

        #expect(sent?.revision == built.revision)
        #expect(sent?.sequenceNumber == built.sequenceNumber)
    }

    @Test @MainActor func `Scheduling a sync doesn't bump the sequence number before sending`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let clock = TestClock()
        let (defaults, suiteName) = try makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var sent: WatchSyncPayload?
        let sender = BookmarkWatchSyncSender(
            userDataStore: application.userDataStore,
            regionsService: application.regionsService,
            bridge: FakeWatchSyncBridge(),
            userDefaults: defaults,
            epochDirectory: epochDirectory,
            debounceInterval: .milliseconds(50),
            clock: clock,
            transport: { sent = $0 }
        )

        sender.scheduleSync()
        await poll(until: { clock.sleeperCount == 1 })
        #expect(defaults.integer(forKey: "BookmarkWatchSyncSender.sequenceNumber") == 0)

        clock.advance(by: .milliseconds(50))
        await poll(until: { sent != nil })
        #expect(sent?.sequenceNumber == 1)
    }

    @Test @MainActor func `Region update notification triggers debounced sync and embeds updated region`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let clock = TestClock()
        let (defaults, suiteName) = try makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var sentPayload: WatchSyncPayload?
        let sender = BookmarkWatchSyncSender(
            userDataStore: application.userDataStore,
            regionsService: application.regionsService,
            bridge: FakeWatchSyncBridge(),
            userDefaults: defaults,
            epochDirectory: epochDirectory,
            debounceInterval: .milliseconds(50),
            clock: clock,
            transport: { payload in
                sentPayload = payload
            }
        )

        let initialRegion = Fixtures.pugetSoundRegion
        application.regionsService.currentRegion = initialRegion
        sender.syncExplicitly()
        #expect(sentPayload?.region?.regionIdentifier == initialRegion.regionIdentifier)

        // Switch to Tampa region and notify through delegate
        let tampaRegion = Fixtures.tampaRegion
        application.regionsService.currentRegion = tampaRegion
        sentPayload = nil
        sender.regionsService(application.regionsService, updatedRegion: tampaRegion)

        // Wait for debounce timer to fire naturally
        await poll(until: { clock.sleeperCount == 1 })
        clock.advance(by: .milliseconds(50))
        await poll(until: { sentPayload != nil })

        let updatedPayload = try #require(sentPayload)
        #expect(updatedPayload.region?.regionIdentifier == tampaRegion.regionIdentifier)
    }

    @Test @MainActor func `Unchanged data re-sync without force does not re-transmit`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let (defaults, suiteName) = try makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var sendCount = 0
        let sender = BookmarkWatchSyncSender(
            userDataStore: application.userDataStore,
            regionsService: application.regionsService,
            bridge: FakeWatchSyncBridge(),
            userDefaults: defaults,
            epochDirectory: epochDirectory,
            debounceInterval: .milliseconds(50),
            transport: { _ in
                sendCount += 1
            }
        )

        sender.syncExplicitly()
        #expect(sendCount == 1)

        // Attempting to sync without force and without any changes
        sender.syncNow(force: false)
        #expect(sendCount == 1)
    }
}
