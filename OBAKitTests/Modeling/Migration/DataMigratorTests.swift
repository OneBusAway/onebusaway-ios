//
//  DataMigratorTests.swift
//  OBAKitTests
//
//  Created by Alan Chu on 1/1/23.
//

import Testing
import Foundation
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class DataMigrator_Tests: OBATestCase {

    var dataLoader: MockDataLoader!
    var migrator: DataMigrator!

    private var dataStore: DataStore!
    private var migrationParameters: DataMigrator.MigrationParameters!

    override init() async throws {
        try await super.init()

        // Load user defaults from the plist fixture.
        let userDefaults = buildUserDefaults()
        let migrationPrefs: [String: Any] = try! Dictionary(plistPath: Fixtures.path(to: "migration_test_preferences.plist"))!

        for (key, value) in migrationPrefs {
            userDefaults.set(value, forKey: key)
        }

        // Get API service ready
        self.dataLoader = (restService.dataLoader as! MockDataLoader)

        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        mockRecentStops()
        mockArrivalsAndDepartures()

        self.migrator = DataMigrator(userDefaults: userDefaults)
        self.dataStore = DataStore()
        self.migrationParameters = DataMigrator.MigrationParameters(forceMigration: false, regionIdentifier: pugetSoundRegionIdentifier, delegate: dataStore)
    }

    override var host: String {
        return "api.pugetsound.onebusaway.org"
    }

    private func mockRecentStops() {
        dataLoader.mock(URLString: "https://api.pugetsound.onebusaway.org/api/where/stop/1_1121.json", with: Fixtures.loadData(file: "stop_1_1121.json"))
        dataLoader.mock(URLString: "https://api.pugetsound.onebusaway.org/api/where/stop/1_11250.json", with: Fixtures.loadData(file: "stop_1_11250.json"))
        dataLoader.mock(URLString: "https://api.pugetsound.onebusaway.org/api/where/stop/1_11370.json", with: Fixtures.loadData(file: "stop_1_11370.json"))
        dataLoader.mock(URLString: "https://api.pugetsound.onebusaway.org/api/where/stop/1_29270.json", with: Fixtures.loadData(file: "stop_1_29270.json"))
        dataLoader.mock(URLString: "https://api.pugetsound.onebusaway.org/api/where/stop/1_29320.json", with: Fixtures.loadData(file: "stop_1_29320.json"))
        dataLoader.mock(URLString: "https://api.pugetsound.onebusaway.org/api/where/stop/1_99610.json", with: Fixtures.loadData(file: "stop_1_99610.json"))
    }

    private func mockArrivalsAndDepartures() {
        dataLoader.mock(URLString: "https://api.pugetsound.onebusaway.org/api/where/arrivals-and-departures-for-stop/1_1121.json", with: Fixtures.loadData(file: "arrivals-and-departures_1_1121.json"))
        dataLoader.mock(URLString: "https://api.pugetsound.onebusaway.org/api/where/arrivals-and-departures-for-stop/1_11250.json", with: Fixtures.loadData(file: "arrivals-and-departures_1_11250.json"))
        dataLoader.mock(URLString: "https://api.pugetsound.onebusaway.org/api/where/arrivals-and-departures-for-stop/1_29270.json", with: Fixtures.loadData(file: "arrivals-and-departures_1_29270.json"))
        dataLoader.mock(URLString: "https://api.pugetsound.onebusaway.org/api/where/arrivals-and-departures-for-stop/1_29320.json", with: Fixtures.loadData(file: "arrivals-and-departures_1_29320.json"))
        dataLoader.mock(URLString: "https://api.pugetsound.onebusaway.org/api/where/arrivals-and-departures-for-stop/1_11370.json", with: Fixtures.loadData(file: "arrivals-and-departures_1_11370.json"))
        dataLoader.mock(URLString: "https://api.pugetsound.onebusaway.org/api/where/arrivals-and-departures-for-stop/1_99610.json", with: Fixtures.loadData(file: "arrivals-and-departures_1_99610.json"))
    }

    @Test func `Migration basic properties`() async throws {
        let report = try await self.migrator.performMigration(migrationParameters, apiService: self.restService)

        // Check results metadata
        #expect(report.dateFinished != nil)
        #expect(report.isFinished)

        // Check User ID
        let userIDMigrationResult = try #require(report.userIDMigrationResult)
        #expect(throws: Never.self, "Expected User ID migration to be successful") {
            try userIDMigrationResult.get()
        }

        let storedUserID = try #require(dataStore.userID, "Expected the userID to be stored.")
        #expect(storedUserID == "B72C5F1A-B8E5-4FB3-A857-CAC6EAC86DE0")

        // Check region
        let storedRegion = try #require(dataStore.region, "Expected the region to be stored.")
        #expect(storedRegion.name == "Puget Sound")
        #expect(storedRegion.identifier == pugetSoundRegionIdentifier, "Expected the region identifier to be stored as \(pugetSoundRegionIdentifier)")
    }

    @Test func `Migration recent stops`() async throws {
        let results = try await self.migrator.performMigration(migrationParameters, apiService: self.restService)

        let recentStopErrors = results.recentStopsMigrationResult.filter { key, value in
            if case Result.failure = value {
                return true
            } else {
                return false
            }
        }

        #expect(recentStopErrors.isEmpty, "Recent stops migration should have no errors")

        // Check stops
        let stops = dataStore.recentStops.sorted(by: { $0.id > $1.id })
        #expect(stops.count == 6)

        let firstStop = try #require(stops.first)
        #expect(firstStop.name == "Capitol Hill Link Station")
        #expect(firstStop.id == "1_99610")
        expectClose(firstStop.coordinate.latitude, 47.6196, within: 0.0001)
        expectClose(firstStop.coordinate.longitude, -122.3204, within: 0.0001)
        #expect(firstStop.routeIDs == ["40_100479"])
        #expect(firstStop.routes.count == 1)

        #expect(stops[1].name == "24th Ave E & E Galer St")
        #expect(stops[2].name == "E John St & Broadway  E")
        #expect(stops[3].name == "15th Ave E & E Galer St")
        #expect(stops[4].name == "10th Ave E & E Galer St")
        #expect(stops[5].name == "Westlake Station - Bay A")
    }

    @Test func `Migration bookmark groups`() async throws {
        _ = try await self.migrator.performMigration(migrationParameters, apiService: self.restService)

        let groups = dataStore.bookmarkGroups.sorted(by: { $1.sortOrder > $0.sortOrder })
        #expect(groups.count == 3)

        #expect(groups[0].name == "Work")
        #expect(groups[0].id.uuidString == "E87AFBD5-6B61-4916-947F-458476ACBF98")
        #expect(groups[0].sortOrder == 1)

        #expect(groups[1].name == "Home")
        #expect(groups[1].id.uuidString == "C8AD00F0-8C30-48B1-B194-E5167E45C80E")
        #expect(groups[1].sortOrder == 2)

        #expect(groups[2].name == "Mika")
        #expect(groups[2].id.uuidString == "7CFB03E7-8C74-4CF6-A415-B1EEE7259812")
        #expect(groups[2].sortOrder == 3)
    }

    @Test func `Migration bookmarks`() async throws {
        let report = try await self.migrator.performMigration(migrationParameters, apiService: self.restService)

        // MARK: Testing the graceful handling of migration failures
        // Get the failing `BookmarkMigration` object, so we can test the dictionary key.
        let failingBookmark = try #require(report.bookmarksMigrationResult.keys.first { bookmark in
            return bookmark.stopID == "1_99610"
        }, "Expected to find a bookmark with a Stop ID of 1_99610")

        // Testing the dictionary key retrieval
        let failingBookmarkResult = try #require(report.bookmarksMigrationResult[failingBookmark], "Expected the migration report to contain Bookmark Migration Results for bookmark with Stop ID 1_99610")

        // Testing that the specific migration error is surfaced in the report.
        // Expected to fail because the bookmark's stop has no active trips.
        #expect(throws: DataMigrationBookmarkError.noActiveTrips) {
            try failingBookmarkResult.get()
        }

        // MARK: Testing the successful bookmark migrations

        let bookmarks = self.dataStore.bookmarks.sorted { lhs, rhs in
            if lhs.routeShortName == rhs.routeShortName {
                return lhs.tripHeadsign! < rhs.tripHeadsign!
            } else {
                return lhs.routeShortName! < rhs.routeShortName!
            }
        }

        #expect(bookmarks.count == 5)
        #expect(bookmarks[0].id != nil)
        #expect(bookmarks[0].groupID?.uuidString == "C8AD00F0-8C30-48B1-B194-E5167E45C80E")
        #expect(bookmarks[0].name == "10 to Home")
        #expect(bookmarks[0].regionIdentifier == pugetSoundRegionIdentifier)
        #expect(bookmarks[0].stopID == "1_29270")
        #expect(bookmarks[0].stop != nil)
        #expect(!bookmarks[0].isFavorite)
        #expect(bookmarks[0].routeShortName == "10")
        #expect(bookmarks[0].routeID == "1_100002")
        #expect(bookmarks[0].sortOrder == Int.max)
        #expect(bookmarks[0].tripHeadsign == "Capitol Hill Via 15th Ave E")

        #expect(bookmarks[1].id != nil)
        #expect(bookmarks[1].groupID?.uuidString == "E87AFBD5-6B61-4916-947F-458476ACBF98")
        #expect(bookmarks[1].name == "10 to Work")
        #expect(bookmarks[1].regionIdentifier == pugetSoundRegionIdentifier)
        #expect(bookmarks[1].stopID == "1_11370")
        #expect(bookmarks[1].stop != nil)
        #expect(!bookmarks[1].isFavorite)
        #expect(bookmarks[1].routeShortName == "10")
        #expect(bookmarks[1].routeID == "1_100002")
        #expect(bookmarks[1].sortOrder == Int.max)
        #expect(bookmarks[1].tripHeadsign == "Downtown Seattle")

        #expect(bookmarks[2].id != nil)
        #expect(bookmarks[2].groupID?.uuidString == "7CFB03E7-8C74-4CF6-A415-B1EEE7259812")
        #expect(bookmarks[2].name == "48 to UW")
        #expect(bookmarks[2].regionIdentifier == pugetSoundRegionIdentifier)
        #expect(bookmarks[2].stopID == "1_29320")
        #expect(bookmarks[2].stop != nil)
        #expect(!bookmarks[2].isFavorite)
        #expect(bookmarks[2].routeShortName == "48")
        #expect(bookmarks[2].routeID == "1_100228")
        #expect(bookmarks[2].sortOrder == Int.max)
        #expect(bookmarks[2].tripHeadsign == "University District")

        #expect(bookmarks[3].id != nil)
        #expect(bookmarks[3].groupID?.uuidString == "7CFB03E7-8C74-4CF6-A415-B1EEE7259812")
        #expect(bookmarks[3].name == "49 to UW")
        #expect(bookmarks[3].regionIdentifier == pugetSoundRegionIdentifier)
        #expect(bookmarks[3].stopID == "1_11250")
        #expect(bookmarks[3].stop != nil)
        #expect(!bookmarks[3].isFavorite)
        #expect(bookmarks[3].routeShortName == "49")
        #expect(bookmarks[3].routeID == "1_100447")
        #expect(bookmarks[3].sortOrder == Int.max)
        #expect(bookmarks[3].tripHeadsign == "University District")

        #expect(bookmarks[4].id != nil)
        #expect(bookmarks[4].groupID == nil)
        #expect(bookmarks[4].name == "Link to CHS")
        #expect(bookmarks[4].regionIdentifier == pugetSoundRegionIdentifier)
        #expect(bookmarks[4].stopID == "1_1121")
        #expect(bookmarks[4].stop != nil)
        #expect(!bookmarks[4].isFavorite)
        #expect(bookmarks[4].routeShortName == "Link")
        #expect(bookmarks[4].routeID == "40_100479")
        #expect(bookmarks[4].sortOrder == Int.max)
        #expect(bookmarks[4].tripHeadsign == "University Of Washington Station")
    }

    // MARK: - TestDelegate

    private class DataStore: DataMigrationDelegate {

        var userID: String?
        var region: MigrationRegion?
        var recentStops = [Stop]()
        var bookmarks = [Bookmark]()

        private var groupsInternal = Set<BookmarkGroup>()
        var bookmarkGroups: [BookmarkGroup] {
            groupsInternal.allObjects
        }

        func migrate(userID: String) {
            self.userID = userID
        }

        func migrate(region: MigrationRegion) {
            self.region = region
        }

        func migrate(recentStop: Stop) {
            recentStops.append(recentStop)
        }

        func migrate(bookmark: Bookmark, group: BookmarkGroup?) {
            bookmark.groupID = group?.id
            bookmarks.append(bookmark)
            if let group = group {
                groupsInternal.insert(group)
            }
        }
    }
}
