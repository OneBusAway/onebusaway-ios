//
//  DataMigrator_Tests.swift
//  OBAKitTests
//
//  Created by Alan Chu on 1/1/23.
//

import XCTest
import Foundation
@testable import OBAKit
@testable import OBAKitCore

class DataMigrator_Tests: OBATestCase {

    var dataLoader: MockDataLoader!
    var migrator: DataMigrator_!

    private var dataStore: DataStore!
    private var migrationParameters: DataMigrator_.MigrationParameters!

    override func setUp() {
        super.setUp()

        // Load user defaults from the plist fixture.
        let userDefaults = buildUserDefaults()
        let migrationPrefs: [String: Any] = try! Dictionary(plistPath: Fixtures.path(to: "migration_test_preferences.plist"))!

        for (key, value) in migrationPrefs {
            userDefaults.set(value, forKey: key)
        }

        // Get API service ready
        self.dataLoader = (betterRESTService.dataLoader as! MockDataLoader)

        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        mockRecentStops()
        mockArrivalsAndDepartures()

        self.migrator = DataMigrator_(userDefaults: userDefaults)
        self.dataStore = DataStore()
        self.migrationParameters = DataMigrator_.MigrationParameters(forceMigration: false, regionIdentifier: pugetSoundRegionIdentifier)
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

    func testMigration_basicProperties() async throws {
        let report = try await self.migrator.performMigration(
            migrationParameters,
            apiService: self.betterRESTService,
            dataStorer: dataStore)

        // Check results metadata
        XCTAssertNotNil(report.dateFinished)
        XCTAssertTrue(report.isFinished)

        // Check User ID
        let userIDMigrationResult = try XCTUnwrap(report.userIDMigrationResult)
        XCTAssertNoThrow(try userIDMigrationResult.get(), "Expected User ID migration to be successful")

        let storedUserID = try XCTUnwrap(dataStore.userID, "Expected the userID to be stored.")
        XCTAssertEqual(storedUserID, "B72C5F1A-B8E5-4FB3-A857-CAC6EAC86DE0")

        // Check region
        let storedRegion = try XCTUnwrap(dataStore.region, "Expected the region to be stored.")
        XCTAssertEqual(storedRegion.name, "Puget Sound")
        XCTAssertEqual(storedRegion.identifier, pugetSoundRegionIdentifier, "Expected the region identifier to be stored as \(pugetSoundRegionIdentifier)")
    }

    func testMigration_recentStops() async throws {
        let results = try await self.migrator.performMigration(
            migrationParameters,
            apiService: self.betterRESTService,
            dataStorer: dataStore)

        let recentStopErrors = results.recentStopsMigrationResult.filter { key, value in
            if case Result.failure = value {
                return true
            } else {
                return false
            }
        }

        XCTAssertTrue(recentStopErrors.isEmpty, "Recent stops migration should have no errors")

        // Check stops
        let stops = dataStore.recentStops.sorted(by: { $0.id > $1.id })
        XCTAssertEqual(stops.count, 6)

        let firstStop = try XCTUnwrap(stops.first)
        XCTAssertEqual(firstStop.name, "Capitol Hill Link Station")
        XCTAssertEqual(firstStop.id, "1_99610")
        XCTAssertEqual(firstStop.coordinate.latitude, 47.6196, accuracy: 0.0001)
        XCTAssertEqual(firstStop.coordinate.longitude, -122.3204, accuracy: 0.0001)
        XCTAssertEqual(firstStop.routeIDs, ["40_100479"])
        XCTAssertEqual(firstStop.routes.count, 1)

        XCTAssertEqual(stops[1].name, "24th Ave E & E Galer St")
        XCTAssertEqual(stops[2].name, "E John St & Broadway  E")
        XCTAssertEqual(stops[3].name, "15th Ave E & E Galer St")
        XCTAssertEqual(stops[4].name, "10th Ave E & E Galer St")
        XCTAssertEqual(stops[5].name, "Westlake Station - Bay A")
    }

    func testMigration_bookmarkGroups() async throws {
        let results = try await self.migrator.performMigration(
            migrationParameters,
            apiService: self.betterRESTService,
            dataStorer: dataStore)

        let groups = dataStore.bookmarkGroups.sorted(by: { $1.sortOrder > $0.sortOrder })
        XCTAssertEqual(groups.count, 3)

        XCTAssertEqual(groups[0].name, "Work")
        XCTAssertEqual(groups[0].id.uuidString, "E87AFBD5-6B61-4916-947F-458476ACBF98")
        XCTAssertEqual(groups[0].sortOrder, 1)

        XCTAssertEqual(groups[1].name, "Home")
        XCTAssertEqual(groups[1].id.uuidString, "C8AD00F0-8C30-48B1-B194-E5167E45C80E")
        XCTAssertEqual(groups[1].sortOrder, 2)

        XCTAssertEqual(groups[2].name, "Mika")
        XCTAssertEqual(groups[2].id.uuidString, "7CFB03E7-8C74-4CF6-A415-B1EEE7259812")
        XCTAssertEqual(groups[2].sortOrder, 3)
    }

    func testMigration_bookmarks() async throws {
        let report = try await self.migrator.performMigration(
            migrationParameters,
            apiService: self.betterRESTService,
            dataStorer: dataStore)

        // MARK: Testing the graceful handling of migration failures
        // Get the failing `BookmarkMigration` object, so we can test the dictionary key.
        let failingBookmark = try XCTUnwrap(report.bookmarksMigrationResult.keys.first { bookmark in
            return bookmark.stopID == "1_99610"
        }, "Expected to find a bookmark with a Stop ID of 1_99610")

        // Testing the dictionary key retrieval
        let failingBookmarkResult = try XCTUnwrap(report.bookmarksMigrationResult[failingBookmark], "Expected the migration report to contain Bookmark Migration Results for bookmark with Stop ID 1_99610")

        // Testing that the specific migration error is surfaced in the report
        XCTAssertThrowsError(try failingBookmarkResult.get(),"The failing bookmark should have a result type of .failure") { error in
            guard let migrationError = error as? MigrationBookmarkError else {
                return XCTFail("Expected the migration error type to be a MigrationBookmarkError")
            }

            XCTAssertEqual(migrationError, .noActiveTrips, "Expected the migration to fail because there are no active trips associated with the bookmark's stop")
        }

        // MARK: Testing the successful bookmark migrations

        let bookmarks = self.dataStore.bookmarks.sorted { lhs, rhs in
            if lhs.routeShortName == rhs.routeShortName {
                return lhs.tripHeadsign! < rhs.tripHeadsign!
            } else {
                return lhs.routeShortName! < rhs.routeShortName!
            }
        }

        XCTAssertEqual(bookmarks.count, 5)
        XCTAssertNotNil(bookmarks[0].id)
        XCTAssertEqual(bookmarks[0].groupID?.uuidString, "C8AD00F0-8C30-48B1-B194-E5167E45C80E")
        XCTAssertEqual(bookmarks[0].name, "10 to Home")
        XCTAssertEqual(bookmarks[0].regionIdentifier, pugetSoundRegionIdentifier)
        XCTAssertEqual(bookmarks[0].stopID, "1_29270")
        XCTAssertNotNil(bookmarks[0].stop)
        XCTAssertFalse(bookmarks[0].isFavorite)
        XCTAssertEqual(bookmarks[0].routeShortName, "10")
        XCTAssertEqual(bookmarks[0].routeID, "1_100002")
        XCTAssertEqual(bookmarks[0].sortOrder, Int.max)
        XCTAssertEqual(bookmarks[0].tripHeadsign, "Capitol Hill Via 15th Ave E")

        XCTAssertNotNil(bookmarks[1].id)
        XCTAssertEqual(bookmarks[1].groupID?.uuidString, "E87AFBD5-6B61-4916-947F-458476ACBF98")
        XCTAssertEqual(bookmarks[1].name, "10 to Work")
        XCTAssertEqual(bookmarks[1].regionIdentifier, pugetSoundRegionIdentifier)
        XCTAssertEqual(bookmarks[1].stopID, "1_11370")
        XCTAssertNotNil(bookmarks[1].stop)
        XCTAssertFalse(bookmarks[1].isFavorite)
        XCTAssertEqual(bookmarks[1].routeShortName, "10")
        XCTAssertEqual(bookmarks[1].routeID, "1_100002")
        XCTAssertEqual(bookmarks[1].sortOrder, Int.max)
        XCTAssertEqual(bookmarks[1].tripHeadsign, "Downtown Seattle")

        XCTAssertNotNil(bookmarks[2].id)
        XCTAssertEqual(bookmarks[2].groupID?.uuidString, "7CFB03E7-8C74-4CF6-A415-B1EEE7259812")
        XCTAssertEqual(bookmarks[2].name, "48 to UW")
        XCTAssertEqual(bookmarks[2].regionIdentifier, pugetSoundRegionIdentifier)
        XCTAssertEqual(bookmarks[2].stopID, "1_29320")
        XCTAssertNotNil(bookmarks[2].stop)
        XCTAssertFalse(bookmarks[2].isFavorite)
        XCTAssertEqual(bookmarks[2].routeShortName, "48")
        XCTAssertEqual(bookmarks[2].routeID, "1_100228")
        XCTAssertEqual(bookmarks[2].sortOrder, Int.max)
        XCTAssertEqual(bookmarks[2].tripHeadsign, "University District")

        XCTAssertNotNil(bookmarks[3].id)
        XCTAssertEqual(bookmarks[3].groupID?.uuidString, "7CFB03E7-8C74-4CF6-A415-B1EEE7259812")
        XCTAssertEqual(bookmarks[3].name, "49 to UW")
        XCTAssertEqual(bookmarks[3].regionIdentifier, pugetSoundRegionIdentifier)
        XCTAssertEqual(bookmarks[3].stopID, "1_11250")
        XCTAssertNotNil(bookmarks[3].stop)
        XCTAssertFalse(bookmarks[3].isFavorite)
        XCTAssertEqual(bookmarks[3].routeShortName, "49")
        XCTAssertEqual(bookmarks[3].routeID, "1_100447")
        XCTAssertEqual(bookmarks[3].sortOrder, Int.max)
        XCTAssertEqual(bookmarks[3].tripHeadsign, "University District")

        XCTAssertNotNil(bookmarks[4].id)
        XCTAssertNil(bookmarks[4].groupID)
        XCTAssertEqual(bookmarks[4].name, "Link to CHS")
        XCTAssertEqual(bookmarks[4].regionIdentifier, pugetSoundRegionIdentifier)
        XCTAssertEqual(bookmarks[4].stopID, "1_1121")
        XCTAssertNotNil(bookmarks[4].stop)
        XCTAssertFalse(bookmarks[4].isFavorite)
        XCTAssertEqual(bookmarks[4].routeShortName, "Link")
        XCTAssertEqual(bookmarks[4].routeID, "40_100479")
        XCTAssertEqual(bookmarks[4].sortOrder, Int.max)
        XCTAssertEqual(bookmarks[4].tripHeadsign, "University Of Washington Station")
    }

    // MARK: - TestDelegate

    private class DataStore: DataMigratorDataStorer {

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
