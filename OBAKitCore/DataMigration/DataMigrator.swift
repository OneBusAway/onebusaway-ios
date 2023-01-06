//
//  DataMigrator.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

public enum DataMigrationError: Error, LocalizedError {
    case invalidAPIService
    case noAPIServiceAvailable
    case noDataToMigrate
    case noMigrationPending

    public var errorDescription: String? {
        switch self {
        case .invalidAPIService:
            return "Invalid API service"
        case .noAPIServiceAvailable:
            return "No API service available"
        case .noDataToMigrate:
            return "No data to migrate"
        case .noMigrationPending:
            return "No migration pending"
        }
    }
}

public enum MigrationBookmarkError: Error, LocalizedError {
    case noActiveTrips

    public var errorDescription: String? {
        switch self {
        case .noActiveTrips:
            return "Bookmark has no active trips"
        }
    }
}

public protocol DataMigrationDelegate {
    func migrate(userID: String) async throws
    func migrate(region: MigrationRegion) async throws
    func migrate(recentStop: Stop) async throws
    func migrate(bookmark: Bookmark, group: BookmarkGroup?) async throws
}
