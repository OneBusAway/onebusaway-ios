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
    static public func createTable(in database: Database) throws {
        try database.create(table: databaseTableName) { table in
            table.column("id", .text).primaryKey()
            table.column("name", .text).notNull()
            table.column("code", .text).notNull()
            table.column("direction", .text).notNull()
            table.column("lat", .double).notNull()
            table.column("lon", .double).notNull()
            table.column("locationType", .integer).notNull()
            table.column("routeIds", .jsonText)
            table.column("wheelchairBoarding", .text).notNull()
        }
    }
}
