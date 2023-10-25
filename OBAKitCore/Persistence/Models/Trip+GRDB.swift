//
//  Trip+GRDB.swift
//  OBAKitCore
// 
//  Copyright © 2023 Open Transit Software Foundation.
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import GRDB

extension Trip: FetchableRecord, PersistableRecord, TableRecord, DatabaseTableCreator {
    public static let databaseTableName: String = "trips"

    static let route = belongsTo(Route.self)
    public var route: QueryInterfaceRequest<Route> {
        request(for: Trip.route)
    }

    public static func createTable(in database: GRDB.Database) throws {
        try database.create(table: Trip.databaseTableName) { table in
            table.column("id", .text).primaryKey()
            table.column("blockId", .text).notNull()
            table.column("direction", .text)
            table.column("routeShortName", .text)
            table.column("serviceId", .text).notNull()
            table.column("shapeId", .text).notNull()
            table.column("timeZone", .text)
            table.column("tripShortName", .text)
            table.column("tripHeadsign", .text)

            table.column("routeId", .text)
                .notNull()
                .references(Route.databaseTableName)
        }
    }

    // Due to `GRDB/EncodableRecord+Encodable.swift:48: Fatal error: single value encoding is not supported` and it currently doesn't play nice with MetaCodable's expanded macro.

    enum Columns: String, ColumnExpression {
        case id
        case blockID = "blockId"
        case routeID = "routeId"
        case serviceID = "serviceId"
        case shapeID = "shapeId"
        case direction, routeShortName, timeZone, tripShortName, tripHeadsign
    }

    public init(row: Row) throws {
        id = row[Columns.id]
        blockID = row[Columns.blockID]
        direction = row[Columns.direction]
        routeID = row[Columns.routeID]
        routeShortName = row[Columns.routeShortName]
        serviceID = row[Columns.serviceID]
        shapeID = row[Columns.shapeID]
        timeZone = row[Columns.timeZone]
        shortName = row[Columns.tripShortName]
        headsign = row[Columns.tripHeadsign]
    }

    public func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.blockID] = blockID
        container[Columns.direction] = direction
        container[Columns.routeID] = routeID
        container[Columns.routeShortName] = routeShortName
        container[Columns.serviceID] = serviceID
        container[Columns.shapeID] = shapeID
        container[Columns.timeZone] = timeZone
        container[Columns.tripShortName] = shortName
        container[Columns.tripHeadsign] = headsign
    }
}
