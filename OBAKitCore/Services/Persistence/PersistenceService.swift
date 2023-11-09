//
//  PersistenceService.swift
//  OBAKitCore
// 
//  Copyright © 2023 Open Transit Software Foundation.
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import os.log
import GRDB

public protocol ReferencesProvider {
    var references: References? { get }
}

extension RESTAPIResponse: ReferencesProvider { }

public actor PersistenceService {
    public struct Configuration {
        public enum DatabaseLocation {
            case disk
            case memory
        }

        public let regionIdentifier: Int
        public let databaseLocation: DatabaseLocation

        public let tableCreators: [DatabaseTableCreator.Type] = [
            Agency.self,
            Stop.self,
            Route.self,
            Trip.self,
            TripDetails.self,
            Situation.self
        ]

        public init(regionIdentifier: Int, databaseLocation: DatabaseLocation) {
            self.regionIdentifier = regionIdentifier
            self.databaseLocation = databaseLocation
        }
    }

    public let configuration: Configuration
    public let logger = os.Logger(subsystem: "OBAKitCore", category: "PersistenceService")
    public let database: DatabaseQueue

    public init(_ configuration: Configuration) throws {
        self.configuration = configuration

        switch configuration.databaseLocation {
        case .disk:
            let fileManager = FileManager.default
            let applicationSupportURL = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let directoryURL = applicationSupportURL
                .appendingPathComponent("regions", isDirectory: true)
                .appendingPathComponent("\(configuration.regionIdentifier)", isDirectory: true)
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            let databaseURL = directoryURL.appendingPathComponent("onebusaway.sqlite")

            logger.info("Opening SQLite at \(databaseURL, privacy: .public).")
            database = try DatabaseQueue(path: databaseURL.path)
        case .memory:
            logger.info("Opening SQLite in memory.")
            database = try DatabaseQueue()
        }

        // Migration registration
        var migrator = DatabaseMigrator()
        migrator.registerMigration("createUsingTableCreators") { db in
            let logger = os.Logger(subsystem: "OBAKitCore", category: "PersistenceService-DatabaseMigrator")
            var additionalTableCreators: [DatabaseTableCreator.Type] = []

            for tableCreator in configuration.tableCreators {
                logger.trace("Creating table: \(String(describing: tableCreator))")
                try tableCreator.createTable(in: db)
                additionalTableCreators.append(contentsOf: tableCreator.additionalTableCreators)
            }

            // Additional tables are usually for relationships. These should be created last, since SQLite needs to reference other tables.
            for additionalCreator in additionalTableCreators {
                logger.trace("Creating additional table: \(String(describing: additionalCreator))")
                try additionalCreator.createTable(in: db)
            }
        }

        migrator.eraseDatabaseOnSchemaChange = true

        try migrator.migrate(database)
    }

    public func processAPIResponse<T: Decodable>(_ apiResponse: RESTAPIResponse<T>) async throws {

        // References are processed first
        try await processReferences(apiResponse)

        guard let persistableRecord = apiResponse.entry as? PersistableRecord else {
            logger.error("Attempted to insert non-PersistableRecord \"\(String(describing: T.self))\". ")
            return
        }

        try await database.write { db in
            try persistableRecord.insert(db, onConflict: .replace)
        }
    }

    public func processAPIResponseAndReturnObject<T: Decodable & PersistableRecord>(_ apiResponse: RESTAPIResponse<T>) async throws -> T {

        // References are processed first
        try await processReferences(apiResponse)
        return try await database.write { db in
            try apiResponse.entry.inserted(db, onConflict: .replace)
        }
    }

    public func processReferences(_ apiResponse: ReferencesProvider) async throws {
        guard let references = apiResponse.references else {
            return
        }

        try await database.write { db in
            for agency in references.agencies {
                try agency.insert(db, onConflict: .replace)
            }

            for route in references.routes {
                try route.insert(db, onConflict: .replace)
            }

            for stop in references.stops {
                try stop.insert(db, onConflict: .replace)
            }

            for trip in references.trips {
                try trip.insert(db, onConflict: .replace)
            }

            // Situation should occur last, since it may reference agencies, routes, stops, trips, etc.
            for situation in references.situations {
                try situation.insert(into: db)
            }
        }
    }
}
