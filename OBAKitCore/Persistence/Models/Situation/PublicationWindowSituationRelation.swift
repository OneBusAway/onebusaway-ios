//
//  PublicationWindowSituationRelation.swift
//  OBAKitCore
// 
//  Copyright © 2023 Open Transit Software Foundation.
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import GRDB
import Foundation
import MetaCodable

@Codable
struct PublicationWindowSituationRelation {
    @CodedAt("situationId")
    let situationID: String
    let from: Date
    let to: Date

    init(situationID: String, from: Date, to: Date) {
        self.situationID = situationID
        self.from = from
        self.to = to
    }
}

extension PublicationWindowSituationRelation: FetchableRecord, PersistableRecord, TableRecord, DatabaseTableCreator {
    static let databaseTableName: String = "publicationwindow_situation_relation"
    
    static private let situation = belongsTo(Situation.self)
    var situation: QueryInterfaceRequest<Situation> {
        request(for: PublicationWindowSituationRelation.situation)
    }

    enum Columns {
        static let situationID = Column(CodingKeys.situationID)
        static let from = Column(CodingKeys.from)
        static let to = Column(CodingKeys.to)
    }

    static func createTable(in database: Database) throws {
        try database.create(table: databaseTableName) { table in
            table.column(Columns.situationID.name, .text)
                .notNull()
                .indexed()
                .references(Situation.databaseTableName, onDelete: .cascade)
            table.column(Columns.from.name, .datetime)
                .notNull()
            table.column(Columns.to.name, .datetime)
                .notNull()
        }
    }
}

// MARK: - Associations
extension Situation {
    static private let publicationWindows = hasMany(PublicationWindowSituationRelation.self)
    var publicationWindows: QueryInterfaceRequest<PublicationWindowSituationRelation> {
        request(for: Situation.publicationWindows)
    }
}
