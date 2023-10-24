//
//  Route+GRDB.swift
//  OBAKitCore
// 
//  Copyright © 2023 Open Transit Software Foundation.
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import GRDB

extension Route: FetchableRecord, PersistableRecord, TableRecord, DatabaseTableCreator {
    static public let databaseTableName: String = "routes"

    public static func createTable(in database: Database) throws {
        try database.create(table: databaseTableName) { table in
            table.column("id", .text).primaryKey()
            table.column("agencyId", .text).notNull()
            table.column("description", .text)
            table.column("longName", .text)
            table.column("shortName", .text).notNull()
            table.column("color", .text)
            table.column("textColor", .text)
            table.column("type", .integer).notNull()
            table.column("url", .text)
        }
    }

    // Due to `GRDB/EncodableRecord+Encodable.swift:48: Fatal error: single value encoding is not supported` and it currently doesn't play nice with MetaCodable's expanded macro.

    enum Columns: String, ColumnExpression {
        case agencyID = "agencyId"
        case id, description, longName, shortName, color, textColor, type, url
    }

    public func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.agencyID] = agencyID
        container[Columns.description] = routeDescription
        container[Columns.longName] = longName
        container[Columns.shortName] = shortName
        container[Columns.color] = color
        container[Columns.textColor] = textColor
        container[Columns.type] = routeType.rawValue
        container[Columns.url] = routeURL?.relativeString
    }
}
