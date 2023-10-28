//
//  ActiveWindowSituationRelation.swift
//  OBAKitCore
// 
//  Copyright © 2023 Open Transit Software Foundation.
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import GRDB
import Foundation

struct ActiveWindowSituationRelation: Codable {
    enum CodingKeys: String, CodingKey {
        case situationID = "situationId"
        case from, to
    }

    let situationID: String
    let from: Date
    let to: Date

    init(situationID: String, from: Date, to: Date) {
        self.situationID = situationID
        self.from = from
        self.to = to
    }
}

extension ActiveWindowSituationRelation: FetchableRecord, PersistableRecord, TableRecord, DatabaseTableCreator {
    static let databaseTableName: String = "activewindow_situation_relation"

    static private let situation = belongsTo(Situation.self)
    var situation: QueryInterfaceRequest<Situation> {
        request(for: ActiveWindowSituationRelation.situation)
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
    static private let activeWindows = hasMany(ActiveWindowSituationRelation.self)
    var activeWindows: QueryInterfaceRequest<ActiveWindowSituationRelation> {
        request(for: Situation.activeWindows)
    }
}
