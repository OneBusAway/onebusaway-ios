//
//  TripDetails+GRDB.swift
//  OBAKitCore
// 
//  Copyright © 2023 Open Transit Software Foundation.
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import GRDB

extension TripDetails: FetchableRecord, PersistableRecord, TableRecord, DatabaseTableCreator {
    static public let databaseTableName: String = "trip_details"

    static private let trip = belongsTo(Trip.self, using: ForeignKey([Columns.tripID]))
    public var trip: QueryInterfaceRequest<Trip> {
        request(for: TripDetails.trip)
    }

    /// If this trip is part of a block and has an incoming trip from another route, this element will provide the incoming trip.
    public var previousTrip: QueryInterfaceRequest<Trip> {
        Trip.filter(id: schedule.previousTripID ?? "")
    }

    /// If this trip is part of a block and has an outgoing trip to another route, this will provide the outgoing trip.
    public var nextTrip: QueryInterfaceRequest<Trip> {
        Trip.filter(id: schedule.nextTripID ?? "")
    }

    enum Columns {
        static let tripID = Column(CodingKeys.tripID)
        static let frequency = Column(CodingKeys.frequency)
        static let serviceDate = Column(CodingKeys.serviceDate)
        static let status = Column(CodingKeys.status)
        static let schedule = Column(CodingKeys.schedule)
        static let situationIDs = Column(CodingKeys.situationIDs)
    }

    public static func createTable(in database: Database) throws {
        try database.create(table: databaseTableName) { table in
            table.column(Columns.tripID.name, .text)
                .notNull()
                .primaryKey()
                .references(Trip.databaseTableName)
            table.column(Columns.frequency.name, .jsonText)
            table.column(Columns.serviceDate.name, .datetime)
                .notNull()
            table.column(Columns.status.name, .jsonText)
            table.column(Columns.schedule.name, .jsonText)
                .notNull()
            table.column(Columns.situationIDs.name, .jsonText)
        }
    }
}
