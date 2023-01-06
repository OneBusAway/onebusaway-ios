//
//  DataMigrator_.swift
//  OBAKitCore
//
//  Created by Alan Chu on 1/1/23.
//

import Foundation

public protocol DataMigrationDelegate: AnyObject {
    func migrate(recentStop: Stop) async throws
    func migrate(userID: String) async throws
    func migrate(region: MigrationRegion) async throws
    func migrate(bookmark: Bookmark, group: BookmarkGroup?) async throws
}

public actor DataMigrator_ {
    public struct MigrationParameters {
        public var forceMigration: Bool
        public var regionIdentifier: RegionIdentifier

        public init(forceMigration: Bool, regionIdentifier: RegionIdentifier) {
            self.forceMigration = forceMigration
            self.regionIdentifier = regionIdentifier
        }
    }

    private struct UserDefaultsKeys {
        static let migrationPending = "DataMigrator.migrationPending"
    }

    // MARK: - DataMigrator properties -

    private let extractor: MigrationDataExtractor
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
        self.extractor = MigrationDataExtractor(defaults: userDefaults)

        self.userDefaults.register(defaults: [
            UserDefaultsKeys.migrationPending: true
        ])
    }

    public func stopMigrationPrompts() {
        userDefaults.set(false, forKey: UserDefaultsKeys.migrationPending)
    }

    public private(set) var isMigrationPending: Bool {
        get {
            return userDefaults.bool(forKey: UserDefaultsKeys.migrationPending)
        } set {
            userDefaults.set(newValue, forKey: UserDefaultsKeys.migrationPending)
        }
    }

    public var shouldPerformMigration: Bool {
        return extractor.hasDataToMigrate && isMigrationPending
    }

    /// Returns whether the `UserDefaults.standard` has data to migrate.
    public static var hasDataToMigrate: Bool {
        return MigrationDataExtractor(defaults: .standard).hasDataToMigrate
    }

    // swiftlint:disable cyclomatic_complexity function_body_length
    public func performMigration(_ parameters: MigrationParameters, apiService: RESTAPIService, delegate: DataMigrationDelegate?) async throws -> MigrationReport {

        // The API service must be configured to the same region as parameters.regionIdentifier.
        guard let apiServiceRegionIdentifier = apiService.configuration.regionIdentifier,
              apiServiceRegionIdentifier == parameters.regionIdentifier else {
            throw DataMigrationError.invalidAPIService
        }

        guard extractor.hasDataToMigrate else {
            throw DataMigrationError.noDataToMigrate
        }

        if !parameters.forceMigration && !isMigrationPending {
            throw DataMigrationError.noMigrationPending
        }

        var results = MigrationReport(dateStarted: Date())

        if let userID = extractor.oldUserID {
            do {
                try await delegate?.migrate(userID: userID)
                results.userIDMigrationResult = .success(())
            } catch {
                results.userIDMigrationResult = .failure(error)
            }
        }

        // Migrating region must be done in sequence since `dataStorer.migrate(region:)`
        // might change the application's current region, which may be a prerequisite
        // of the other migration operations below.
        if let region = extractor.extractRegion() {
            do {
                try await delegate?.migrate(region: region)
                results.regionMigrationResult = .success(())
            } catch {
                results.regionMigrationResult = .failure(error)
            }
        }

        let recentStopsToMigrate = extractor.extractRecentStops() ?? []
        let bookmarksToMigrate = extractor.extractBookmarks() ?? []
        let bookmarkGroupsToMigrate = extractor.extractBookmarkGroups() ?? []

        // Migration is making network calls, which may be parallelized.
        async let migratedRecentStops = await migrateRecentStops(recentStopsToMigrate, apiService: apiService)
        async let migratedBookmarkGroups = await migrateBookmarkGroups(
            bookmarkGroupsToMigrate,
            regionIdentifier: parameters.regionIdentifier,
            apiService: apiService
        )

        async let migratedBookmarks = await migrateBookmarks(
            bookmarksToMigrate,
            group: nil,
            regionIdentifier: parameters.regionIdentifier,
            apiService: apiService
        )

        // Wait for the parallelized operations to finish.
        _ = await [migratedRecentStops, migratedBookmarkGroups, migratedBookmarks]

        for migratedRecentStop in await migratedRecentStops {
            results.recentStopsMigrationResult[migratedRecentStop.key] = await doTaskIfNoError(migratedRecentStop.value) { stop in
                try await delegate?.migrate(recentStop: stop)
            }
        }

        for migratedBookmarkGroup in await migratedBookmarkGroups {
            let bookmarkGroup = BookmarkGroup(migrationGroup: migratedBookmarkGroup.bookmarkGroup)
            var newResults = MigrationBookmarkGroupResult(bookmarkGroup: migratedBookmarkGroup.bookmarkGroup, bookmarks: [:])
            for migratedBookmark in migratedBookmarkGroup.bookmarks {
                newResults.bookmarks[migratedBookmark.key] = await doTaskIfNoError(migratedBookmark.value) { bookmark in
                    try await delegate?.migrate(bookmark: bookmark, group: bookmarkGroup)
                }
            }

            results.bookmarkGroupsMigrationResult[migratedBookmarkGroup.bookmarkGroup] = newResults
        }

        for migratedBookmark in await migratedBookmarks {
            results.bookmarksMigrationResult[migratedBookmark.key] = await doTaskIfNoError(migratedBookmark.value) { bookmark in
                try await delegate?.migrate(bookmark: bookmark, group: nil)
            }
        }

        results.dateFinished = Date()

        return results
    }

    /// Helper method for doing additional work (`nextTask`) on a result. If the provided result already contains a failure, then the additional work is not executed and this method will return the original error.
    func doTaskIfNoError<ResultType>(_ result: Result<ResultType, Error>, block: (ResultType) async throws -> Void) async -> Result<ResultType, Error> {
        switch result {
        case .failure(let error):
            return .failure(error)
        case .success(let resultType):
            do {
                try await block(resultType)
                return .success(resultType)
            } catch {
                return .failure(error)
            }
        }
    }

    // MARK: - Bookmarks
    public struct MigrationBookmarkGroupResult {
        public let bookmarkGroup: MigrationBookmarkGroup
        public internal(set) var bookmarks: [MigrationBookmark: Result<Bookmark, Error>]
    }

    private func migrateBookmarkGroups(_ bookmarkGroups: [MigrationBookmarkGroup], regionIdentifier: RegionIdentifier, apiService: RESTAPIService) async -> [MigrationBookmarkGroupResult] {
        var results: [MigrationBookmarkGroupResult] = []
        results.reserveCapacity(bookmarkGroups.count)

        // Parallelize migrationBookmarks.
        return await withTaskGroup(of: MigrationBookmarkGroupResult.self) { taskGroup in
            for bookmarkGroup in bookmarkGroups {
                taskGroup.addTask {
                    let bookmarks = await self.migrateBookmarks(bookmarkGroup.bookmarks, group: bookmarkGroup, regionIdentifier: regionIdentifier, apiService: apiService)
                    return MigrationBookmarkGroupResult(bookmarkGroup: bookmarkGroup, bookmarks: bookmarks)
                }
            }

            // Combine results.
            var results: [MigrationBookmarkGroupResult] = []
            results.reserveCapacity(bookmarkGroups.count)

            for await result in taskGroup {
                results.append(result)
            }

            return results
        }
    }

    private func migrateBookmarks(_ bookmarks: [MigrationBookmark], group: MigrationBookmarkGroup?, regionIdentifier: RegionIdentifier, apiService: RESTAPIService) async -> [MigrationBookmark: Result<Bookmark, Error>] {

        @Sendable
        func migrateBookmark(_ migrationBookmark: MigrationBookmark) async -> Result<Bookmark, Error> {
            do {
                let newBookmark: Bookmark
                if migrationBookmark.isStopBookmark {
                    newBookmark = try await migrateStopBookmark(migrationBookmark, group: group, regionIdentifier: regionIdentifier, apiService: apiService)
                } else {
                    newBookmark = try await migrateTripBookmark(migrationBookmark, group: group, regionIdentifier: regionIdentifier, apiService: apiService)
                }
                return .success(newBookmark)
            } catch {
                return .failure(error)
            }
        }

        return await withTaskGroup(of: (MigrationBookmark, Result<Bookmark, Error>).self) { taskGroup in
            var results: [MigrationBookmark: Result<Bookmark, Error>] = [:]
            results.reserveCapacity(bookmarks.count)

            for bookmark in bookmarks {
                taskGroup.addTask {
                    return (bookmark, await migrateBookmark(bookmark))
                }
            }

            for await (migrationBookmark, migrationResult) in taskGroup {
                results[migrationBookmark] = migrationResult
            }

            return results
        }
    }

    private func migrateStopBookmark(_ migrationBookmark: MigrationBookmark, group: MigrationBookmarkGroup?, regionIdentifier: RegionIdentifier, apiService: RESTAPIService) async throws -> Bookmark {
        let stop = try await apiService.getStop(id: migrationBookmark.stopID)
        return Bookmark(name: migrationBookmark.name, regionIdentifier: regionIdentifier, stop: stop.entry)
    }

    private func migrateTripBookmark(_ migrationBookmark: MigrationBookmark, group: MigrationBookmarkGroup?, regionIdentifier: RegionIdentifier, apiService: RESTAPIService) async throws -> Bookmark {
        guard let tripKey = TripBookmarkKey(migrationBookmark: migrationBookmark) else {
            fatalError("todo fix me")
        }

        let response = try await apiService.getArrivalsAndDeparturesForStop(id: migrationBookmark.stopID, minutesBefore: 0, minutesAfter: 60)

        guard let arrDep = response.list.arrivalsAndDepartures.tripKeyGroupedElements[tripKey]?.first else {
            throw MigrationBookmarkError.noActiveTrips
        }

        return Bookmark(name: migrationBookmark.name, regionIdentifier: regionIdentifier, arrivalDeparture: arrDep)
    }

    // MARK: - Recent Stops
    private func migrateRecentStops(_ recentStops: [MigrationRecentStop], apiService: RESTAPIService) async -> [MigrationRecentStop: Result<Stop, Error>] {

        return await withTaskGroup(of: (MigrationRecentStop, Result<Stop, Error>).self) { group in
            var results: [MigrationRecentStop: Result<Stop, Error>] = [:]
            results.reserveCapacity(recentStops.count)

            for recentStop in recentStops {
                group.addTask {
                    do {
                        let response = try await apiService.getStop(id: recentStop.stopID)
                        return (recentStop, .success(response.entry))
                    } catch {
                        return (recentStop, .failure(error))
                    }
                }
            }

            for await (migrationRecentStop, migrationResult) in group {
                results[migrationRecentStop] = migrationResult
            }

            return results
        }
    }
}
