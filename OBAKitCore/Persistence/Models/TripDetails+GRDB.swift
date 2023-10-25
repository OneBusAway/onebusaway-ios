//
//  TripDetails+GRDB.swift
//  OBAKitCore
// 
//  Copyright © 2023 Open Transit Software Foundation.
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import GRDB

extension TripStopTime: DatabaseValueConvertible { }

extension TripDetails: FetchableRecord, PersistableRecord, TableRecord, DatabaseTableCreator {
    static public let databaseTableName: String = "trip_details"

    static private let trip = belongsTo(Trip.self, using: ForeignKey([Columns.tripID]))
    public var trip: QueryInterfaceRequest<Trip> {
        request(for: TripDetails.trip)
    }

    static private let previousTrip = belongsTo(Trip.self, using: ForeignKey([Columns.previousTripId]))
    public var previousTrip: QueryInterfaceRequest<Trip> {
        request(for: TripDetails.previousTrip)
    }

    static private let nextTrip = belongsTo(Trip.self, using: ForeignKey([Columns.nextTripId]))
    public var nextTrip: QueryInterfaceRequest<Trip> {
        request(for: TripDetails.nextTrip)
    }

    public static func createTable(in database: Database) throws {
        try database.create(table: databaseTableName) { table in
//            table.column("frequency", .jsonText)
            table.column("tripId", .text)
                .primaryKey()
                .references(Trip.databaseTableName)
            table.column("serviceDate", .datetime).notNull()
//            table.column("status", .jsonText)   // We might want to omit this for offline.
            table.column("timeZone", .text)
//            table.column("stopTimes", .jsonText)
            table.column("previousTripId", .text)
                .references(Trip.databaseTableName)
            table.column("nextTripId", .text)
                .references(Trip.databaseTableName)

            // situationIDs is a many-to-many.
        }
    }

    enum Columns: String, ColumnExpression {
        case tripID = "tripId"
        case serviceDate, /*status, */timeZone, stopTimes, previousTripId, nextTripId
    }

    public init(row: Row) throws {
        frequency = nil
        tripID = row[Columns.tripID]
        serviceDate = row[Columns.serviceDate]
        status = nil
        timeZone = row[Columns.timeZone]
        stopTimes = []
        previousTripID = row[Columns.previousTripId]
        nextTripID = row[Columns.nextTripId]
        situationIDs = []
    }

    public func encode(to container: inout PersistenceContainer) throws {
        container[Columns.tripID] = tripID
        container[Columns.serviceDate] = serviceDate
//        if let status {
//            container[Columns.status] = status
//        }
        container[Columns.timeZone] = timeZone
//        container[Columns.stopTimes] = stopTimes
        container[Columns.previousTripId] = previousTripID
        container[Columns.nextTripId] = nextTripID
    }
}

//extension Collection: DatabaseValueConvertible where Element == TripStopTime { }
