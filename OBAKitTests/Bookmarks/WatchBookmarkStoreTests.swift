//
//  WatchBookmarkStoreTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

@Suite(.serialized)
struct WatchBookmarkStoreTests {

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "WatchBookmarkStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makePayload(sequenceNumber: Int64, epoch: UUID? = nil, stopID: String, name: String, bookmarkID: UUID = UUID()) throws -> WatchSyncPayload {
        let bookmark = WatchBookmark(
            id: bookmarkID,
            name: name,
            regionIdentifier: 1,
            stopID: stopID,
            stopName: "Stop \(stopID)",
            latitude: 47.6,
            longitude: -122.3,
            isFavorite: false
        )
        return try WatchSyncPayload(
            schemaVersion: 1,
            sequenceNumber: sequenceNumber,
            epoch: epoch,
            bookmarks: [bookmark],
            groups: [],
            region: nil
        )
    }

    @Test @MainActor func `New sender epoch is accepted unconditionally even with lower sequence number`() throws {
        let defaults = makeUserDefaults()
        let store = WatchBookmarkStore(userDefaults: defaults)

        let epochA = UUID()
        let epochB = UUID()

        let payloadEpochA = try makePayload(sequenceNumber: 50, epoch: epochA, stopID: "1_100", name: "Old Phone Stop")
        #expect(store.update(payload: payloadEpochA) == true)
        #expect(store.payload?.sequenceNumber == 50)
        #expect(store.payload?.epoch == epochA)

        // Deliver epoch B with sequence 1 (e.g. phone app reinstalled or restored from older backup)
        let payloadEpochB = try makePayload(sequenceNumber: 1, epoch: epochB, stopID: "1_200", name: "Reinstalled Phone Stop")
        #expect(store.update(payload: payloadEpochB) == true)
        #expect(store.payload?.sequenceNumber == 1)
        #expect(store.payload?.epoch == epochB)
        #expect(store.bookmarks.first?.name == "Reinstalled Phone Stop")
    }

    @Test @MainActor func `Initial load restores persisted payload from UserDefaults`() throws {
        let defaults = makeUserDefaults()
        let payload = try makePayload(sequenceNumber: 1, stopID: "1_100", name: "Persisted Stop")
        let data = try payload.encodeToBinaryPlist()
        defaults.set(data, forKey: WatchBookmarkStore.payloadKey)

        let store = WatchBookmarkStore(userDefaults: defaults)

        #expect(store.payload == payload)
        #expect(store.bookmarks.count == 1)
        #expect(store.bookmarks.first?.name == "Persisted Stop")
    }

    @Test @MainActor func `Duplicate payload is ignored`() throws {
        let defaults = makeUserDefaults()
        let store = WatchBookmarkStore(userDefaults: defaults)
        let payload = try makePayload(sequenceNumber: 1, stopID: "1_100", name: "Stop 100")

        let firstApplied = store.update(payload: payload)
        #expect(firstApplied == true)
        #expect(store.bookmarks.count == 1)

        let duplicateApplied = store.update(payload: payload)
        #expect(duplicateApplied == false)
    }

    @Test @MainActor func `Same revision with advancing sequence number is persisted and older sequence is rejected`() throws {
        let defaults = makeUserDefaults()
        let store = WatchBookmarkStore(userDefaults: defaults)

        let bookmarkID = UUID()
        let p1 = try makePayload(sequenceNumber: 1, stopID: "1_100", name: "Same Bookmark", bookmarkID: bookmarkID)
        let p3 = try makePayload(sequenceNumber: 3, stopID: "1_100", name: "Same Bookmark", bookmarkID: bookmarkID)

        #expect(p1.revision == p3.revision)

        // First application with sequence 1
        #expect(store.update(payload: p1) == true)
        #expect(store.payload?.sequenceNumber == 1)

        // Same revision arriving with advancing sequence number 3 must be persisted
        #expect(store.update(payload: p3) == true)
        #expect(store.payload?.sequenceNumber == 3)

        // Replaying older sequence number 1 with same revision must be rejected
        #expect(store.update(payload: p1) == false)
        #expect(store.payload?.sequenceNumber == 3)

        // Replaying identical sequence number 3 is rejected as duplicate
        #expect(store.update(payload: p3) == false)
        #expect(store.payload?.sequenceNumber == 3)
    }

    @Test @MainActor func `Out of order older payload is rejected`() throws {
        let defaults = makeUserDefaults()
        let store = WatchBookmarkStore(userDefaults: defaults)

        let payload2 = try makePayload(sequenceNumber: 2, stopID: "1_200", name: "Newer Stop")
        let payload1 = try makePayload(sequenceNumber: 1, stopID: "1_100", name: "Older Stop")

        let appliedNew = store.update(payload: payload2)
        #expect(appliedNew == true)
        #expect(store.bookmarks.first?.name == "Newer Stop")

        // Older sequence number arrives late
        let appliedOld = store.update(payload: payload1)
        #expect(appliedOld == false)
        #expect(store.bookmarks.first?.name == "Newer Stop")
    }

    @Test @MainActor func `Same sequence number resolves deterministically`() throws {
        let defaults = makeUserDefaults()
        let store = WatchBookmarkStore(userDefaults: defaults)

        let p1 = try makePayload(sequenceNumber: 5, stopID: "1_A", name: "Candidate A")
        let p2 = try makePayload(sequenceNumber: 5, stopID: "1_B", name: "Candidate B")

        let (first, second) = p1.revision < p2.revision ? (p1, p2) : (p2, p1)

        #expect(store.update(payload: first) == true)
        #expect(store.payload?.revision == first.revision)

        // Second candidate has higher revision hash, so it deterministically wins
        #expect(store.update(payload: second) == true)
        #expect(store.payload?.revision == second.revision)

        // Attempting to re-apply the lower revision candidate is rejected
        #expect(store.update(payload: first) == false)
        #expect(store.payload?.revision == second.revision)
    }

    @Test @MainActor func `Empty payload clears bookmarks and groups and persists`() throws {
        let defaults = makeUserDefaults()
        let store = WatchBookmarkStore(userDefaults: defaults)

        let initial = try makePayload(sequenceNumber: 1, stopID: "1_100", name: "To Delete")
        #expect(store.update(payload: initial) == true)
        #expect(store.bookmarks.count == 1)

        let emptyPayload = try WatchSyncPayload(
            schemaVersion: 1,
            sequenceNumber: 2,
            bookmarks: [],
            groups: [],
            region: nil
        )

        #expect(store.update(payload: emptyPayload) == true)
        #expect(store.bookmarks.isEmpty)
        #expect(store.groups.isEmpty)

        // Check persisted data in UserDefaults decodes to empty bookmarks
        let restoredStore = WatchBookmarkStore(userDefaults: defaults)
        #expect(restoredStore.bookmarks.isEmpty)
        #expect(restoredStore.payload == emptyPayload)
    }

    @Test @MainActor func `Clear resets store in memory and in defaults`() throws {
        let defaults = makeUserDefaults()
        let store = WatchBookmarkStore(userDefaults: defaults)

        let payload = try makePayload(sequenceNumber: 1, stopID: "1_100", name: "Stop")
        #expect(store.update(payload: payload) == true)

        store.clear()

        #expect(store.payload == nil)
        #expect(store.bookmarks.isEmpty)
        #expect(defaults.data(forKey: WatchBookmarkStore.payloadKey) == nil)
    }
}
