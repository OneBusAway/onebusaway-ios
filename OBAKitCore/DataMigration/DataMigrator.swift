//
//  DataMigrator.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

// swiftlint:disable cyclomatic_complexity function_body_length

public enum DataMigrationError: Error {
    case noAPIServiceAvailable
    case noDataToMigrate
    case noMigrationPending
}

public enum MigrationBookmarkError: Error {
    case noActiveTrips
}

public protocol DataMigrationDelegate: NSObjectProtocol {
    func migrate(userID: String)
    func migrate(region: MigrationRegion)
    func migrate(recentStop: Stop)
    func migrate(bookmark: Bookmark, group: BookmarkGroup?)
}

public struct DataMigrationResult {
    public let migrationBookmarks: [MigrationBookmark]
    public let migrationBookmarkGroups: [MigrationBookmarkGroup]
    public let failedBookmarks: [(Error, MigrationBookmark)]
    public let bookmarks: [Bookmark]

    public let migrationRecentStops: [MigrationRecentStop]
    public let failedRecentStops: [(Error, MigrationRecentStop)]
    public let recentStops: [Stop]
}

public class DataMigrator: NSObject {
    private let extractor: MigrationDataExtractor
    private weak var delegate: DataMigrationDelegate?
    private let application: CoreApplication
    private let userDefaults: UserDefaults

    private var writeQueue = DispatchQueue(label: "org.onebusaway.iphone.data-migrator")

    public init(userDefaults: UserDefaults, delegate: DataMigrationDelegate, application: CoreApplication) {
        self.userDefaults = userDefaults
        self.extractor = MigrationDataExtractor(defaults: userDefaults)
        self.delegate = delegate
        self.application = application

        super.init()

        self.userDefaults.register(defaults: [
            UserDefaultsKeys.migrationPending: true
        ])
    }

    deinit {
        for op in recentStopOperations {
            op.cancel()
        }
    }

    private struct UserDefaultsKeys {
        static let migrationPending = "DataMigrator.migrationPending"
    }

    public func stopMigrationPrompts() {
        userDefaults.set(false, forKey: UserDefaultsKeys.migrationPending)
    }

    public var shouldPerformMigration: Bool {
        return hasDataToMigrate && userDefaults.bool(forKey: UserDefaultsKeys.migrationPending)
    }

    public var hasDataToMigrate: Bool {
        extractor.hasDataToMigrate
    }

    /// Performs the data migration, informing the caller via the `completion` callback when the process has completed.
    /// - Parameter forceMigration: Allows you to control whether the migration should be performed whether or not it has happened before.
    /// - Parameter completion: Invoked on migration completion to inform the caller of the result.
    public func performMigration(forceMigration: Bool, completion: @escaping (Result<DataMigrationResult, DataMigrationError>) -> Void) {
        guard extractor.hasDataToMigrate else {
            DispatchQueue.main.async {
                completion(.failure(DataMigrationError.noDataToMigrate))
            }
            return
        }

        if !forceMigration {
            guard userDefaults.bool(forKey: UserDefaultsKeys.migrationPending) else {
                DispatchQueue.main.async {
                    completion(.failure(DataMigrationError.noMigrationPending))
                }
                return
            }
        }

        if let userID = extractor.oldUserID {
            delegate?.migrate(userID: userID)
        }

        if let region = extractor.extractRegion() {
            delegate?.migrate(region: region)
        }

        guard
            let currentRegion = application.currentRegion,
            let apiService = application.restAPIService
        else {
            DispatchQueue.main.async {
                completion(.failure(DataMigrationError.noAPIServiceAvailable))
            }
            return
        }

        apiService.networkQueue.isSuspended = true

        let completionOp = BlockOperation { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.stopMigrationPrompts()
                completion(.success(self.buildMigrationResult()))
            }
        }

        var unqueuedOperations = [Operation]()

        if let recentStops = extractor.extractRecentStops() {
            recentStopOperations = migrateRecentStops(recentStops, apiService: apiService)

            for op in recentStopOperations {
                completionOp.addDependency(op)
            }

            unqueuedOperations.append(contentsOf: recentStopOperations)
        }

        if let looseBookmarks = extractor.extractBookmarks() {
            let bookmarkOps = migrateBookmarks(looseBookmarks, group: nil, currentRegion: currentRegion, apiService: apiService)

            bookmarksOperations.append(contentsOf: bookmarkOps)

            for op in bookmarkOps {
                completionOp.addDependency(op)
            }

            unqueuedOperations.append(contentsOf: bookmarkOps)
        }

        if let groups = extractor.extractBookmarkGroups() {
            for g in groups {
                let bookmarkOps = migrateBookmarks(g.bookmarks, group: g, currentRegion: currentRegion, apiService: apiService)

                bookmarksOperations.append(contentsOf: bookmarkOps)

                for op in bookmarkOps {
                    completionOp.addDependency(op)
                }

                unqueuedOperations.append(contentsOf: bookmarkOps)
            }
        }

        apiService.enqueueOperation(completionOp)

        for op in unqueuedOperations {
            apiService.enqueueOperation(op)
        }

        apiService.networkQueue.isSuspended = false
    }

    // MARK: - Extractor

    private lazy var extractorRecentStops: [MigrationRecentStop]? = extractor.extractRecentStops()
    private lazy var extractorBookmarks: [MigrationBookmark]? = extractor.extractBookmarks()
    private lazy var extractorBookmarkGroups: [MigrationBookmarkGroup]? = extractor.extractBookmarkGroups()

    // MARK: - Results

    private func buildMigrationResult() -> DataMigrationResult {
        return DataMigrationResult(
            migrationBookmarks: extractorBookmarks ?? [],
            migrationBookmarkGroups: extractorBookmarkGroups ?? [],
            failedBookmarks: failedBookmarks,
            bookmarks: bookmarks,
            migrationRecentStops: extractorRecentStops ?? [],
            failedRecentStops: failedRecentStops,
            recentStops: recentStops
        )
    }

    // MARK: - Bookmark

    private func migrateBookmarks(
        _ bookmarks: [MigrationBookmark],
        group: MigrationBookmarkGroup?,
        currentRegion: Region,
        apiService: RESTAPIService
    ) -> [DecodableOperation<RESTAPIResponse<StopArrivals>>] {
        return bookmarks.compactMap { migrationBookmark -> DecodableOperation<RESTAPIResponse<StopArrivals>>? in
            guard
                !migrationBookmark.isStopBookmark,
                let tripKey = TripBookmarkKey(migrationBookmark: migrationBookmark)
            else {
                return nil
            }

            let op = apiService.getArrivalsAndDeparturesForStop(id: migrationBookmark.stopID, minutesBefore: 0, minutesAfter: 60, enqueue: false)

            op.complete { [weak self] result in
                guard let self = self else { return }

                switch result {
                case .failure(let error):
                    self.failedBookmarks.append((error, migrationBookmark))
                case .success(let response):
                    if let arrDep = response.list.arrivalsAndDepartures.tripKeyGroupedElements[tripKey]?.first {
                        let bookmark = Bookmark(name: migrationBookmark.name, regionIdentifier: currentRegion.regionIdentifier, arrivalDeparture: arrDep)
                        self.storeBookmark(bookmark, migrationGroup: group)
                    }
                    else {
                        self.failedBookmarks.append((MigrationBookmarkError.noActiveTrips, migrationBookmark))
                    }
                }
            }
            return op
        }
    }

    private func storeBookmark(_ bookmark: Bookmark, migrationGroup: MigrationBookmarkGroup?) {
        writeQueue.async { [weak self] in
            guard let self = self else { return }
            let group = BookmarkGroup(migrationGroup: migrationGroup)
            bookmark.groupID = group?.id
            self.bookmarks.append(bookmark)
            self.delegate?.migrate(bookmark: bookmark, group: group)
        }
    }

    private var bookmarks = [Bookmark]()

    private var bookmarksOperations = [DecodableOperation<RESTAPIResponse<StopArrivals>>]()

    private var failedBookmarks = [(Error, MigrationBookmark)]()

    private func storeFailedBookmark(error: Error, migrationBookmark: MigrationBookmark) {
        writeQueue.async {
            self.failedBookmarks.append((error, migrationBookmark))
        }
    }

    // MARK: - Recent Stops

    private func migrateRecentStops(_ recentStops: [MigrationRecentStop], apiService: RESTAPIService) -> [DecodableOperation<RESTAPIResponse<Stop>>] {
        let ops = recentStops.map { rs -> DecodableOperation<RESTAPIResponse<Stop>> in
            let op = apiService.getStop(id: rs.stopID, enqueue: false)

            op.complete { [weak self] result in
                guard let self = self else { return }

                switch result {
                case .failure(let error):
                    self.storeFailedRecentStop(error: error, migrationRecentStop: rs)
                case .success(let response):
                    self.storeRecentStop(response.list)
                }
            }

            return op
        }

        return ops
    }

    private var recentStopOperations = [DecodableOperation<RESTAPIResponse<Stop>>]()

    private var failedRecentStops = [(Error, MigrationRecentStop)]()

    private func storeFailedRecentStop(error: Error, migrationRecentStop: MigrationRecentStop) {
        writeQueue.sync {
            self.failedRecentStops.append((error, migrationRecentStop))
        }
    }

    private var recentStops = [Stop]()

    private func storeRecentStop(_ stop: Stop) {
        writeQueue.sync { [weak self] in
            guard let self = self else { return }
            self.recentStops.append(stop)
            self.delegate?.migrate(recentStop: stop)
        }
    }
}
