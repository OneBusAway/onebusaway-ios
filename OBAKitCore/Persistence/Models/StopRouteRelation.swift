//
//  StopRouteRelation.swift
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
/// Many-to-many table for associating Stops and Routes. Access via `Route.stops` or `Stop.routes`.
struct StopRouteRelation {
    @CodedAt("stopId")
    let stopID: String

    @CodedAt("routeId")
    let routeID: String

    init(stopID: String, routeID: String) {
        self.stopID = stopID
        self.routeID = routeID
    }
}

extension StopRouteRelation: FetchableRecord, PersistableRecord, TableRecord, DatabaseTableCreator {
    static let databaseTableName: String = "stop_route_relation"

    static let stop = belongsTo(Stop.self)
    static let route = belongsTo(Route.self)

    static func createTable(in database: Database) throws {
        try database.create(table: Self.databaseTableName) { table in
            table.column("stopId")
                .notNull()
                .indexed()
                .references(Stop.databaseTableName, onDelete: nil)

            table.column("routeId")
                .notNull()
                .indexed()
                .references(Route.databaseTableName, onDelete: nil)

            table.primaryKey(["stopId", "routeId"])
        }
    }
}

// MARK: - Associations
extension Route {
    static private let stopForRoutes = hasMany(StopRouteRelation.self)
    static private let stops = hasMany(Stop.self, through: stopForRoutes, using: StopRouteRelation.stop)
    public var stops: QueryInterfaceRequest<Stop> {
        request(for: Route.stops)
    }
}

extension Stop {
    static private let stopForRoutes = hasMany(StopRouteRelation.self)
    static private let routes = hasMany(Route.self, through: stopForRoutes, using: StopRouteRelation.route)
    public var routes: QueryInterfaceRequest<Route> {
        request(for: Stop.routes)
    }
}
