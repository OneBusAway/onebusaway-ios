//
//  AffectedSituationRelation.swift
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
struct AffectedSituationRelation {
    @CodedAt("situationId")
    let situationID: String

    @CodedAt("agencyId")
    public let agencyID: Agency.ID?

    @CodedAt("applicationId")
    public let applicationID: String?

    @CodedAt("directionId")
    public let directionID: String?

    @CodedAt("routeId")
    public let routeID: RouteID?

    @CodedAt("stopId")
    public let stopID: StopID?

    @CodedAt("tripId")
    public let tripID: TripIdentifier?

    init(situationID: String, agencyID: Agency.ID?, applicationID: String?, directionID: String?, routeID: RouteID?, stopID: StopID?, tripID: TripIdentifier?) {
        self.situationID = situationID
        self.agencyID = agencyID
        self.applicationID = applicationID
        self.directionID = directionID
        self.routeID = routeID
        self.stopID = stopID
        self.tripID = tripID
    }

    init(situationID: String, _ affectedEntityREST: AffectedEntityREST) {
        self.init(situationID: situationID, agencyID: affectedEntityREST.agencyID, applicationID: affectedEntityREST.applicationID, directionID: affectedEntityREST.directionID, routeID: affectedEntityREST.routeID, stopID: affectedEntityREST.stopID, tripID: affectedEntityREST.tripID)
    }
}

extension AffectedSituationRelation: FetchableRecord, PersistableRecord, TableRecord, DatabaseTableCreator {
    static let databaseTableName: String = "affected_situation_relation"

    // MARK: - Associations
    static private let situation = belongsTo(Situation.self)
    var situation: QueryInterfaceRequest<Situation> {
        request(for: AffectedSituationRelation.situation)
    }

//    static private let agency = belongsTo(Agency.self)
//    var agency: QueryInterfaceRequest<Agency> {
//        request(for: AffectedSituationRelation.agency)
//    }

    static private let route = belongsTo(Route.self)
    var route: QueryInterfaceRequest<Route> {
        request(for: AffectedSituationRelation.route)
    }

    static private let stop = belongsTo(Stop.self)
    var stop: QueryInterfaceRequest<Stop> {
        request(for: AffectedSituationRelation.stop)
    }

    static private let trip = belongsTo(Trip.self)
    var trip: QueryInterfaceRequest<Trip> {
        request(for: AffectedSituationRelation.trip)
    }

    // MARK: - Database

    enum Columns {
        static let situationID = Column(CodingKeys.situationID)
        static let agencyID = Column(CodingKeys.agencyID)
        static let applicationID = Column(CodingKeys.applicationID)
        static let directionID = Column(CodingKeys.directionID)
        static let routeID = Column(CodingKeys.routeID)
        static let stopID = Column(CodingKeys.stopID)
        static let tripID = Column(CodingKeys.tripID)
    }

    static func createTable(in database: Database) throws {
        try database.create(table: databaseTableName) { table in
            table.column(Columns.situationID.name, .text)
                .notNull()
                .indexed()
                .references(Situation.databaseTableName, onDelete: .cascade)
            table.column(Columns.agencyID.name, .text)
//                .references()
            table.column(Columns.applicationID.name, .text)
            table.column(Columns.directionID.name, .text)
            table.column(Columns.routeID.name, .text)
                .references(Route.databaseTableName)
            table.column(Columns.stopID.name, .text)
                .references(Stop.databaseTableName)
            table.column(Columns.tripID.name, .text)
                .references(Trip.databaseTableName)
        }
    }
}

extension Situation {
    static private let affectedEntities = hasMany(AffectedSituationRelation.self)
    var affectedEntities: QueryInterfaceRequest<AffectedSituationRelation> {
        request(for: Situation.affectedEntities)
    }
}
