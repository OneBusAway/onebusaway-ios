//
//  WatchSyncPayloadTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
@testable import OBAKitCore

@Suite(.serialized)
struct WatchSyncPayloadTests {

    private func makeSamplePayload() throws -> WatchSyncPayload {
        let b1 = WatchBookmark(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            groupID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            name: "Work Commute",
            regionIdentifier: 1,
            stopID: "1_100",
            stopName: "3rd Ave & Pike St",
            stopDirection: "S",
            latitude: 47.6097,
            longitude: -122.3378,
            isFavorite: true,
            routeID: "1_100228",
            routeShortName: "40",
            tripHeadsign: "Downtown"
        )

        let b2 = WatchBookmark(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            groupID: nil,
            name: "Home Stop",
            regionIdentifier: 1,
            stopID: "1_200",
            stopName: "Fremont Ave N & N 34th St",
            stopDirection: "N",
            latitude: 47.6512,
            longitude: -122.3501,
            isFavorite: false
        )

        let group = WatchBookmarkGroup(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            name: "Commute"
        )

        return try WatchSyncPayload(
            schemaVersion: 1,
            bookmarks: [b1, b2],
            groups: [group],
            region: nil
        )
    }

    @Test func `Binary plist encoding and decoding round trip parity`() throws {
        let original = try makeSamplePayload()
        let data = try original.encodeToBinaryPlist()
        let decoded = try WatchSyncPayload.decode(fromBinaryPlist: data)

        #expect(decoded == original)
        #expect(decoded.schemaVersion == 1)
        #expect(decoded.revision == original.revision)
        #expect(decoded.bookmarks.count == 2)
        #expect(decoded.groups.count == 1)

        let first = try #require(decoded.bookmarks.first)
        #expect(first.name == "Work Commute")
        #expect(first.isTripBookmark == true)
        #expect(first.routeShortName == "40")
        #expect(first.tripHeadsign == "Downtown")

        let second = try #require(decoded.bookmarks.last)
        #expect(second.name == "Home Stop")
        #expect(second.isTripBookmark == false)
        #expect(second.routeShortName == nil)
    }

    @Test func `SHA-256 revision stability across identical payloads`() throws {
        let payload1 = try makeSamplePayload()
        let payload2 = try makeSamplePayload()

        #expect(payload1.revision == payload2.revision)
        #expect(!payload1.revision.isEmpty)
        #expect(payload1.revision.count == 64)
    }

    @Test func `Modified bookmark changes revision hash`() throws {
        let original = try makeSamplePayload()

        let modifiedBookmark = WatchBookmark(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            groupID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            name: "Work Commute Modified",
            regionIdentifier: 1,
            stopID: "1_100",
            stopName: "3rd Ave & Pike St",
            stopDirection: "S",
            latitude: 47.6097,
            longitude: -122.3378,
            isFavorite: true,
            routeID: "1_100228",
            routeShortName: "40",
            tripHeadsign: "Downtown"
        )

        let modifiedPayload = try WatchSyncPayload(
            schemaVersion: 1,
            bookmarks: [modifiedBookmark],
            groups: original.groups,
            region: nil
        )

        #expect(original.revision != modifiedPayload.revision)
    }

    @Test func `32-bit integer safety in DTO models`() throws {
        let maxInt32Bookmark = WatchBookmark(
            id: UUID(),
            name: "Max Range Stop",
            regionIdentifier: Int32.max,
            stopID: "stop_max",
            stopName: "Border Station",
            latitude: 45.0,
            longitude: -120.0,
            isFavorite: true
        )

        let payload = try WatchSyncPayload(
            schemaVersion: Int32.max,
            bookmarks: [maxInt32Bookmark],
            groups: [],
            region: nil
        )

        let data = try payload.encodeToBinaryPlist()
        let decoded = try WatchSyncPayload.decode(fromBinaryPlist: data)

        #expect(decoded.schemaVersion == Int32.max)
        #expect(decoded.bookmarks.first?.regionIdentifier == Int32.max)
    }

    @Test func `WatchBookmark initializer from core Bookmark model`() throws {
        let stop = Stop(
            id: "1_10914",
            name: "15th Ave NE & NE Campus Pkwy",
            direction: "S",
            location: CLLocation(latitude: 47.6564, longitude: -122.3121)
        )
        let groupID = UUID()
        let coreBookmark = Bookmark(
            name: "University Stop",
            regionIdentifier: 1,
            stop: stop
        )
        coreBookmark.groupID = groupID

        let watchBookmark = WatchBookmark(bookmark: coreBookmark)

        #expect(watchBookmark.id == coreBookmark.id)
        #expect(watchBookmark.groupID == groupID)
        #expect(watchBookmark.name == "University Stop")
        #expect(watchBookmark.regionIdentifier == 1)
        #expect(watchBookmark.stopID == "1_10914")
        #expect(watchBookmark.stopName == "15th Ave NE & NE Campus Pkwy")
        #expect(watchBookmark.stopDirection == "S")
        #expect(watchBookmark.latitude == 47.6564)
        #expect(watchBookmark.longitude == -122.3121)
        #expect(watchBookmark.isTripBookmark == false)
    }

    @Test func `WatchBookmarkGroup initializer from core BookmarkGroup model`() {
        let groupID = UUID()
        let coreGroup = BookmarkGroup(name: "Night Routes", id: groupID, sortOrder: 5)
        let watchGroup = WatchBookmarkGroup(group: coreGroup)

        #expect(watchGroup.id == groupID)
        #expect(watchGroup.name == "Night Routes")
    }
}
