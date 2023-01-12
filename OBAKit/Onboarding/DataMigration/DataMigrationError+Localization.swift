//
//  DataMigrationError+Localization.swift
//  OBAKit
//
//  Created by Alan Chu on 1/6/23.
//

import OBAKitCore

extension DataMigrationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidAPIService(let explanation):
            return explanation      // Not localized.
        case .noAPIServiceAvailable:
            return OBALoc("data_migration_bulletin.errors.no_api_service_available", value: "Check your internet connection and try again.", comment: "An error message that appears when the user needs to have data migrated, but is not connected to the Internet.")
        case .noDataToMigrate:
            return OBALoc("data_migration_bulletin.errors.no_data_to_migrate", value: "No data to upgrade", comment: "An error message that appears when the data migrator runs but no data can be migrated.")
        case .noMigrationPending:
            return OBALoc("data_migration_bulletin.errors.no_migration_pending", value: "No data migration is pending", comment: "An error message that appears when the data migrator runs without a pending migration.")
        }
    }
}

extension DataMigrationBookmarkError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noActiveTrips:
            return "Bookmark has no active trips"   // Not localized.
        }
    }
}
