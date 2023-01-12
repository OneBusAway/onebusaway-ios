//
//  DataMigratorResults.swift
//  OBAKitCore
//
//  Created by Alan Chu on 1/1/23.
//

import Foundation

extension DataMigrator {
    public struct MigrationReport: Identifiable {
        public var isFinished: Bool {
            dateFinished != nil
        }

        public let id = UUID()
        public let dateStarted: Date
        public var dateFinished: Date? {
            willSet {
                if let dateFinished {
                    precondition(dateFinished >= dateStarted, "dateFinished must be later than dateStarted")
                }
            }
        }

        public var userIDMigrationResult: Result<Void, Error>?
        public var regionMigrationResult: Result<Void, Error>?

        public var recentStopsMigrationResult: [MigrationRecentStop: Result<Stop, Error>] = [:]
        public var bookmarksMigrationResult: [MigrationBookmark: Result<Bookmark, Error>] = [:]
        public var bookmarkGroupsMigrationResult: [MigrationBookmarkGroup: MigrationBookmarkGroupResult] = [:]
    }
}
