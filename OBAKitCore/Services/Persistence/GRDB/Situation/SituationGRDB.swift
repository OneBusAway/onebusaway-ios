//
//  SituationGRDB.swift
//  OBAKitCore
// 
//  Copyright © 2023 Open Transit Software Foundation.
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import GRDB
import Foundation

extension Situation: FetchableRecord, PersistableRecord, TableRecord, DatabaseTableCreator {
    static public let databaseTableName: String = "situations"

    static public var additionalTableCreators: [DatabaseTableCreator.Type] = [
        ActiveWindowSituationRelation.self,
        PublicationWindowSituationRelation.self,
        AffectedSituationRelation.self
    ]

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let creationTime = Column(CodingKeys.creationTime)
        static let reason = Column(CodingKeys.reason)
        static let severity = Column(CodingKeys.severity)
        static let description = Column(CodingKeys.description)
        static let summary = Column(CodingKeys.summary)
        static let url = Column(CodingKeys.url)
        static let consequences = Column(CodingKeys.consequences)
    }

    static public func createTable(in database: GRDB.Database) throws {
        try database.create(table: databaseTableName) { table in
            table.column(Columns.id.name, .text)
                .primaryKey()
                .notNull()

            table.column(Columns.creationTime.name, .datetime).notNull()
            table.column(Columns.reason.name, .text).notNull()
            table.column(Columns.severity.name, .text).notNull()

            table.column(Columns.description.name, .jsonText)
            table.column(Columns.summary.name, .jsonText)
            table.column(Columns.url.name, .jsonText)
            table.column(Columns.consequences.name, .jsonText)
        }
    }
}

// MARK: - SituationREST → SituationGRDB
extension SituationREST {
    func insert(into database: Database) throws {
        // First, insert everything except for relationships.
        let situationToInsert = Situation(id: id, creationTime: creationTime, description: description, reason: reason, severity: severity, summary: summary, url: url, consequences: consequences)
        try situationToInsert.insert(database, onConflict: .replace)

        for allAffect in self.allAffects {
            let relation = AffectedSituationRelation(situationID: situationToInsert.id, allAffect)
            try relation.insert(database, onConflict: .replace)
        }

        for activeWindow in activeWindows {
            let relation = ActiveWindowSituationRelation(situationID: situationToInsert.id, from: activeWindow.from, to: activeWindow.to)
            try relation.insert(database, onConflict: .replace)
        }

        for publicationWindow in publicationWindows {
            let relation = PublicationWindowSituationRelation(situationID: situationToInsert.id, from: publicationWindow.from, to: publicationWindow.to)
            try relation.insert(database, onConflict: .replace)
        }
    }
}
