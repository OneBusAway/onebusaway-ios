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

    // MARK: - Associations
    static let route = belongsTo(Route.self)

    /// The Route served by this trip.
    public var route: QueryInterfaceRequest<Route> {
        request(for: Trip.route)
    }

    // MARK: - DatabaseTableCreator methods

    public static func createTable(in database: GRDB.Database) throws {
        try database.create(table: Trip.databaseTableName) { table in
            table.column(Columns.id.name, .text)
                .notNull()
                .primaryKey()
            table.column(Columns.blockID.name, .text).notNull()
            table.column(Columns.direction.name, .text)
            table.column(Columns.routeShortName.name, .text)
            table.column(Columns.serviceID.name, .text).notNull()
            table.column(Columns.shapeID.name, .text).notNull()
            table.column(Columns.timeZone.name, .text)
            table.column(Columns.shortName.name, .text)
            table.column(Columns.headsign.name, .text)
            table.column(Columns.routeID.name, .text)
                .notNull()
                .references(Route.databaseTableName)
        }
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let blockID = Column(CodingKeys.blockID)
        static let direction = Column(CodingKeys.direction)
        static let routeID = Column(CodingKeys.routeID)
        static let routeShortName = Column(CodingKeys.routeShortName)
        static let serviceID = Column(CodingKeys.serviceID)
        static let shapeID = Column(CodingKeys.shapeID)
        static let timeZone = Column(CodingKeys.timeZone)
        static let shortName = Column(CodingKeys.shortName)
        static let headsign = Column(CodingKeys.headsign)
    }
}
