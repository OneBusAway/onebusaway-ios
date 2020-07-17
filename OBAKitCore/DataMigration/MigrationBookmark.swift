//
//  MigrationBookmark.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

// MARK: - MigrationBookmark

@objc public class MigrationBookmark: NSObject, NSCoding {
    public let name: String
    public let stopID: String
    public let regionID: Int?
    public let routeShortName: String
    public let tripHeadsign: String
    public let routeID: String
    public let sortOrder: Int?

    required public init?(coder: NSCoder) {
        guard
            let name = coder.decodeObject(forKey: "name") as? String,
            let stopID = coder.decodeObject(forKey: "stopId") as? String,
            let regionID = coder.decodeObject(forKey: "regionIdentifier") as? Int?,
            let routeShortName = coder.decodeObject(forKey: "routeShortName") as? String,
            let tripHeadsign = coder.decodeObject(forKey: "tripHeadsign") as? String,
            let routeID = coder.decodeObject(forKey: "routeID") as? String,
            let sortOrder = coder.decodeObject(forKey: "sortOrder") as? Int?
        else { return nil }

        self.name = name
        self.stopID = stopID
        self.regionID = regionID
        self.routeShortName = routeShortName
        self.tripHeadsign = tripHeadsign
        self.routeID = routeID
        self.sortOrder = sortOrder
    }

    public func encode(with coder: NSCoder) { fatalError("This class only supports initialization of an old object. You can't save it back!") }
}

// MARK: - MigrationBookmarkGroup

@objc public class MigrationBookmarkGroup: NSObject, NSCoding {
    public let todayScreenVisible: Bool
    public let name: String?
    public let open: Bool
    public let uuid: String
    public let sortOrder: Int
    public let bookmarks: [MigrationBookmark]

    required public init?(coder: NSCoder) {
        guard
            coder.containsValue(forKey: "name"),
            let uuid = coder.decodeObject(forKey: "UUID") as? String,
            let bookmarks = coder.decodeObject(forKey: "bookmarks") as? [MigrationBookmark]
        else { return nil }

        self.todayScreenVisible = coder.decodeInteger(forKey: "bookmarkGroupType") == 1

        self.name = coder.decodeObject(forKey: "name") as? String ?? nil
        self.open = coder.decodeBool(forKey: "open")
        self.uuid = uuid
        self.sortOrder = coder.decodeInteger(forKey: "sortOrder")
        self.bookmarks = bookmarks
    }

    public func encode(with coder: NSCoder) { fatalError("This class only supports initialization of an old object. You can't save it back!") }
}

// MARK: - Initializer Extensions

extension TripBookmarkKey {
    init(migrationBookmark: MigrationBookmark) {
        self.init(stopID: migrationBookmark.stopID, routeShortName: migrationBookmark.routeShortName, routeID: migrationBookmark.routeID, tripHeadsign: migrationBookmark.tripHeadsign)
    }
}

extension BookmarkGroup {
    convenience init?(migrationGroup: MigrationBookmarkGroup?) {
        guard
            let migrationGroup = migrationGroup,
            let uuid = UUID(optionalUUIDString: migrationGroup.uuid)
        else {
            return nil
        }

        self.init(name: migrationGroup.name ?? "", id: uuid, sortOrder: migrationGroup.sortOrder)
    }
}
