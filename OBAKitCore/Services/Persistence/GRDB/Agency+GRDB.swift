//
//  Agency+GRDB.swift
//  OBAKitCore
// 
//  Copyright © 2023 Open Transit Software Foundation.
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import GRDB

extension Agency: FetchableRecord, PersistableRecord, TableRecord, DatabaseTableCreator {
    public static let databaseTableName: String = "agencies"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let disclaimer = Column(CodingKeys.disclaimer)
        static let email = Column(CodingKeys.email)
        static let fareURL = Column(CodingKeys.fareURL)
        static let language = Column(CodingKeys.language)
        static let phone = Column(CodingKeys.phone)
        static let isPrivateService = Column(CodingKeys.isPrivateService)
        static let timeZone = Column(CodingKeys.timeZone)
        static let agencyURL = Column(CodingKeys.agencyURL)
    }

    public static func createTable(in database: Database) throws {
        try database.create(table: databaseTableName) { table in
            table.column(Columns.id.name, .text)
                .notNull()
                .primaryKey()

            table.column(Columns.name.name, .text).notNull()
            table.column(Columns.disclaimer.name, .text)
            table.column(Columns.email.name, .text)
            table.column(Columns.fareURL.name, .text)
            table.column(Columns.language.name, .text).notNull()
            table.column(Columns.phone.name, .text).notNull()
            table.column(Columns.isPrivateService.name, .boolean).notNull()
            table.column(Columns.timeZone.name, .text).notNull()
            table.column(Columns.agencyURL.name, .text).notNull()
        }
    }

    public init(row: Row) throws {
        id = row[Columns.id]
        name = row[Columns.name]
        disclaimer = row[Columns.disclaimer]
        email = row[Columns.email]
        fareURL = row[Columns.fareURL]
        language = row[Columns.language]
        phone = row[Columns.phone]
        isPrivateService = row[Columns.isPrivateService]
        timeZone = row[Columns.timeZone]
        agencyURL = row[Columns.agencyURL]
    }

    public func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.name] = name
        container[Columns.disclaimer] = disclaimer
        container[Columns.email] = email
        container[Columns.fareURL] = fareURL
        container[Columns.language] = language
        container[Columns.phone] = phone
        container[Columns.isPrivateService] = isPrivateService
        container[Columns.timeZone] = timeZone
        container[Columns.agencyURL] = agencyURL
    }
}
