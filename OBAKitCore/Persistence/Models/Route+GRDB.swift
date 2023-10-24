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

    static private let agency = belongsTo(Agency.self)
    var agency: QueryInterfaceRequest<Agency> {
        request(for: Route.agency)
    }

    public static func createTable(in database: Database) throws {
        try database.create(table: databaseTableName) { table in
            table.column(Columns.id.name, .text)
                .notNull()
                .primaryKey()
            table.column(Columns.agencyID.name, .text)
                .notNull()
                .references(Agency.databaseTableName)
            table.column(Columns.description.name, .text)
            table.column(Columns.longName.name, .text)
            table.column(Columns.shortName.name, .text).notNull()
            table.column(Columns.color.name, .text)
            table.column(Columns.textColor.name, .text)
            table.column(Columns.routeType.name, .integer).notNull()
            table.column(Columns.routeURL.name, .text)
        }
    }

    enum Columns {
        static let agencyID = Column(CodingKeys.agencyID)
        static let id = Column(CodingKeys.id)
        static let routeDescription = Column(CodingKeys.routeDescription)
        static let description = Column(CodingKeys.routeDescription)
        static let longName = Column(CodingKeys.longName)
        static let shortName = Column(CodingKeys.shortName)
        static let color = Column(CodingKeys.color)
        static let textColor = Column(CodingKeys.textColor)
        static let routeType = Column(CodingKeys.routeType)
        static let routeURL = Column(CodingKeys.routeURL)
    }
}

extension Route.RouteType: DatabaseValueConvertible { }
