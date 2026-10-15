//
//  WatchSyncPayload.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import CryptoKit

// MARK: - WatchBookmark

public struct WatchBookmark: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let groupID: UUID?
    public let name: String
    public let regionIdentifier: Int32
    public let stopID: StopID
    public let stopName: String
    public let stopDirection: String?
    public let latitude: Double
    public let longitude: Double
    public let isFavorite: Bool
    public let routeID: RouteID?
    public let routeShortName: String?
    public let tripHeadsign: String?

    public var isTripBookmark: Bool {
        routeID != nil
    }

    public init(
        id: UUID,
        groupID: UUID? = nil,
        name: String,
        regionIdentifier: Int32,
        stopID: StopID,
        stopName: String,
        stopDirection: String? = nil,
        latitude: Double,
        longitude: Double,
        isFavorite: Bool,
        routeID: RouteID? = nil,
        routeShortName: String? = nil,
        tripHeadsign: String? = nil
    ) {
        self.id = id
        self.groupID = groupID
        self.name = name
        self.regionIdentifier = regionIdentifier
        self.stopID = stopID
        self.stopName = stopName
        self.stopDirection = stopDirection
        self.latitude = latitude
        self.longitude = longitude
        self.isFavorite = isFavorite
        self.routeID = routeID
        self.routeShortName = routeShortName
        self.tripHeadsign = tripHeadsign
    }

    public init(bookmark: Bookmark) {
        self.id = bookmark.id
        self.groupID = bookmark.groupID
        self.name = bookmark.name
        self.regionIdentifier = Int32(clamping: bookmark.regionIdentifier)
        self.stopID = bookmark.stopID
        self.stopName = bookmark.stop.name
        self.stopDirection = Formatters.directionAbbreviation(bookmark.stop.direction)
        self.latitude = bookmark.stop.location.coordinate.latitude
        self.longitude = bookmark.stop.location.coordinate.longitude
        self.isFavorite = bookmark.isFavorite
        self.routeID = bookmark.routeID
        self.routeShortName = bookmark.routeShortName
        self.tripHeadsign = bookmark.tripHeadsign
    }

    public var stop: Stop {
        Stop(watchBookmark: self)
    }
}

// MARK: - WatchBookmarkGroup

public struct WatchBookmarkGroup: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }

    public init(group: BookmarkGroup) {
        self.id = group.id
        self.name = group.name
    }
}

// MARK: - WatchSyncPayload

public struct WatchSyncPayload: Codable, Sendable, Equatable {
    public let schemaVersion: Int32
    public let revision: String
    public let bookmarks: [WatchBookmark]
    public let groups: [WatchBookmarkGroup]
    public let region: Region?

    public init(
        schemaVersion: Int32 = 1,
        bookmarks: [WatchBookmark],
        groups: [WatchBookmarkGroup],
        region: Region?
    ) throws {
        let revision = try Self.computeRevision(
            schemaVersion: schemaVersion,
            bookmarks: bookmarks,
            groups: groups,
            region: region
        )
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.bookmarks = bookmarks
        self.groups = groups
        self.region = region
    }

    public init(
        schemaVersion: Int32,
        revision: String,
        bookmarks: [WatchBookmark],
        groups: [WatchBookmarkGroup],
        region: Region?
    ) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.bookmarks = bookmarks
        self.groups = groups
        self.region = region
    }

    public static func computeRevision(
        schemaVersion: Int32,
        bookmarks: [WatchBookmark],
        groups: [WatchBookmarkGroup],
        region: Region?
    ) throws -> String {
        let unhashedPayload = WatchSyncPayload(
            schemaVersion: schemaVersion,
            revision: "",
            bookmarks: bookmarks,
            groups: groups,
            region: region
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(unhashedPayload)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public func encodeToBinaryPlist() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(self)
    }

    public static func decode(fromBinaryPlist data: Data) throws -> WatchSyncPayload {
        let decoder = PropertyListDecoder()
        return try decoder.decode(WatchSyncPayload.self, from: data)
    }
}
