//
//  Stop+GRDB.swift
//  OBAKitCore
// 
//  Copyright © 2023 Open Transit Software Foundation.
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import GRDB

extension Stop: FetchableRecord, PersistableRecord, TableRecord, DatabaseTableCreator {
    static public let databaseTableName: String = "stops"

    // MARK: - DatabaseTableCreator methods
    static public var additionalTableCreators: [DatabaseTableCreator.Type] {
        [StopRouteRelation.self]
    }

    static public func createTable(in database: Database) throws {
        try database.create(table: databaseTableName) { table in
            table.column(Columns.id.name, .text).notNull().primaryKey()
            table.column(Columns.name.name, .text).notNull()
            table.column(Columns.code.name, .text).notNull()
            table.column(Columns.direction.name, .text)
            table.column(Columns.latitude.name, .double).notNull()
            table.column(Columns.longitude.name, .double).notNull()
            table.column(Columns.locationType.name, .integer).notNull()
            table.column(Columns.wheelchairBoarding.name, .text).notNull()
            table.column(Columns.routeIDs.name, .jsonText)
        }
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let code = Column(CodingKeys.code)
        static let direction = Column(CodingKeys.direction)
        static let latitude = Column(CodingKeys.latitude)
        static let longitude = Column(CodingKeys.longitude)
        static let locationType = Column(CodingKeys.locationType)
        static let wheelchairBoarding = Column(CodingKeys.wheelchairBoarding)
        static let routeIDs = Column(CodingKeys.routeIDs)
    }

    public func aroundInsert(_ db: Database, insert: () throws -> InsertionSuccess) throws {
        _ = try insert()

        for routeID in routeIDs {
            try StopRouteRelation(stopID: self.id, routeID: routeID)
                .insert(db, onConflict: .replace)
        }
    }
}
