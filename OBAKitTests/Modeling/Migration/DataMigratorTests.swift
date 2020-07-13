//
//  DataMigratorTests.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 5/12/20.
//

import Foundation
import Nimble
import XCTest
@testable import OBAKit
@testable import OBAKitCore

// xswiftlint:disable force_try function_body_length weak_delegate

class DataMigratorTests: OBATestCase {

    var dataLoader: MockDataLoader!
    var migrator: DataMigrator!
    var coreApp: CoreApplication!
    var migrationPrefs: [String: Any]!
    var queue: OperationQueue!
    var defaults: UserDefaults!
    var testDelegate: TestDelegate!

    override func setUp() {
        super.setUp()

        queue = OperationQueue()

        defaults = buildUserDefaults()
        migrationPrefs = try! [String: Any](plistPath: Fixtures.path(to: "migration_test_preferences.plist"))!
        for (k, v) in migrationPrefs {
            defaults.set(v, forKey: k)
        }

        dataLoader = MockDataLoader(testName: name)

        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        let locManager = MockAuthorizedLocationManager(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let locationService = LocationService(userDefaults: defaults, locationManager: locManager)

        let config = CoreAppConfig(regionsBaseURL: regionsURL, obacoBaseURL: obacoURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)

        coreApp = CoreApplication(config: config)

        testDelegate = TestDelegate()

        migrator = DataMigrator(userDefaults: config.userDefaults, delegate: testDelegate, application: coreApp)
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

    func testMigration_basicProperties() {
        mockRecentStops()
        mockArrivalsAndDepartures()

        waitUntil { done in
            self.migrator.performMigration(forceMigration: false) { result in
                switch result {
                case .failure:
                    XCTFail("Should not fail.")
                case .success:
                    expect(self.testDelegate.userID) == "B72C5F1A-B8E5-4FB3-A857-CAC6EAC86DE0"
                    let region = self.testDelegate.region!
                    expect(region.name) == "Puget Sound"
                    expect(region.identifier) == 1
                }
                done()
            }
        }
    }

    func testMigration_recentStops() {
        mockRecentStops()
        mockArrivalsAndDepartures()

        waitUntil { done in
            self.migrator.performMigration(forceMigration: false) { result in
                switch result {
                case .failure:
                    XCTFail("Should not fail.")
                case .success:
                    let stops = self.testDelegate.recentStops.sorted(by: {$0.id > $1.id})
                    expect(stops.count) == 6

                    expect(stops[0].name) == "Capitol Hill Link Station"
                    expect(stops[0].id) == "1_99610"
                    expect(stops[0].coordinate.latitude).to(beCloseTo(47.6196))
                    expect(stops[0].coordinate.longitude).to(beCloseTo(-122.3204))
                    expect(stops[0].routeIDs) == ["40_100479"]
                    expect(stops[0].routes.count) == 1

                    expect(stops[1].name) == "24th Ave E & E Galer St"
                    expect(stops[2].name) == "E John St & Broadway  E"
                    expect(stops[3].name) == "15th Ave E & E Galer St"
                    expect(stops[4].name) == "10th Ave E & E Galer St"
                    expect(stops[5].name) == "Westlake Station - Bay A"
                }

                done()
            }
        }
    }

    func testMigration_bookmarkGroups() {
        mockRecentStops()
        mockArrivalsAndDepartures()

        waitUntil { done in
            self.migrator.performMigration(forceMigration: false) { result in
                switch result {
                case .failure:
                    XCTFail("Should not fail.")
                case .success:
                    let groups = self.testDelegate.bookmarkGroups.sorted(by: {$1.sortOrder > $0.sortOrder})
                    expect(groups.count) == 3

                    expect(groups[0].name) == "Work"
                    expect(groups[0].id.uuidString) == "E87AFBD5-6B61-4916-947F-458476ACBF98"
                    expect(groups[0].sortOrder) == 1

                    expect(groups[1].name) == "Home"
                    expect(groups[1].id.uuidString) == "C8AD00F0-8C30-48B1-B194-E5167E45C80E"
                    expect(groups[1].sortOrder) == 2

                    expect(groups[2].name) == "Mika"
                    expect(groups[2].id.uuidString) == "7CFB03E7-8C74-4CF6-A415-B1EEE7259812"
                    expect(groups[2].sortOrder) == 3
                }

                done()
            }
        }
    }

    func testMigration_bookmarks() {
        mockRecentStops()
        mockArrivalsAndDepartures()

        waitUntil { done in
            self.migrator.performMigration(forceMigration: false) { result in
                switch result {
                case .failure:
                    XCTFail("Should not fail.")
                case .success(let migrationResult):
                    let failedBookmarks = migrationResult.failedBookmarks
                    let failedRecentStops = migrationResult.failedRecentStops

                    let bookmarks = self.testDelegate.bookmarks.sorted(by: { b1, b2 in
                        if b1.routeShortName == b2.routeShortName {
                            return b1.tripHeadsign! < b2.tripHeadsign!
                        }
                        else {
                            return b1.routeShortName! < b2.routeShortName!
                        }
                    })

                    expect(failedBookmarks.count) == 1
                    expect(failedRecentStops.count) == 0

                    expect(bookmarks.count) == 5

                    expect(bookmarks[0].id).toNot(beNil())
                    expect(bookmarks[0].groupID!.uuidString) == "C8AD00F0-8C30-48B1-B194-E5167E45C80E"
                    expect(bookmarks[0].name) == "10 to Home"
                    expect(bookmarks[0].regionIdentifier) == 1
                    expect(bookmarks[0].stopID) == "1_29270"
                    expect(bookmarks[0].stop).toNot(beNil())
                    expect(bookmarks[0].isFavorite) == false
                    expect(bookmarks[0].routeShortName) == "10"
                    expect(bookmarks[0].routeID) == "1_100002"
                    expect(bookmarks[0].sortOrder) == Int.max
                    expect(bookmarks[0].tripHeadsign) == "Capitol Hill Via 15th Ave E"

                    expect(bookmarks[1].id).toNot(beNil())
                    expect(bookmarks[1].groupID!.uuidString) == "E87AFBD5-6B61-4916-947F-458476ACBF98"
                    expect(bookmarks[1].name) == "10 to Work"
                    expect(bookmarks[1].regionIdentifier) == 1
                    expect(bookmarks[1].stopID) == "1_11370"
                    expect(bookmarks[1].stop).toNot(beNil())
                    expect(bookmarks[1].isFavorite) == false
                    expect(bookmarks[1].routeShortName) == "10"
                    expect(bookmarks[1].routeID) == "1_100002"
                    expect(bookmarks[1].sortOrder) == Int.max
                    expect(bookmarks[1].tripHeadsign) == "Downtown Seattle"

                    expect(bookmarks[2].id).toNot(beNil())
                    expect(bookmarks[2].groupID!.uuidString) == "7CFB03E7-8C74-4CF6-A415-B1EEE7259812"
                    expect(bookmarks[2].name) == "48 to UW"
                    expect(bookmarks[2].regionIdentifier) == 1
                    expect(bookmarks[2].stopID) == "1_29320"
                    expect(bookmarks[2].stop).toNot(beNil())
                    expect(bookmarks[2].isFavorite) == false
                    expect(bookmarks[2].routeShortName) == "48"
                    expect(bookmarks[2].routeID) == "1_100228"
                    expect(bookmarks[2].sortOrder) == Int.max
                    expect(bookmarks[2].tripHeadsign) == "University District"

                    expect(bookmarks[3].id).toNot(beNil())
                    expect(bookmarks[3].groupID?.uuidString) == "7CFB03E7-8C74-4CF6-A415-B1EEE7259812"
                    expect(bookmarks[3].name) == "49 to UW"
                    expect(bookmarks[3].regionIdentifier) == 1
                    expect(bookmarks[3].stopID) == "1_11250"
                    expect(bookmarks[3].stop).toNot(beNil())
                    expect(bookmarks[3].isFavorite) == false
                    expect(bookmarks[3].routeShortName) == "49"
                    expect(bookmarks[3].routeID) == "1_100447"
                    expect(bookmarks[3].sortOrder) == Int.max
                    expect(bookmarks[3].tripHeadsign) == "University District"

                    expect(bookmarks[4].id).toNot(beNil())
                    expect(bookmarks[4].groupID).to(beNil())
                    expect(bookmarks[4].name) == "Link to CHS"
                    expect(bookmarks[4].regionIdentifier) == 1
                    expect(bookmarks[4].stopID) == "1_1121"
                    expect(bookmarks[4].stop).toNot(beNil())
                    expect(bookmarks[4].isFavorite) == false
                    expect(bookmarks[4].routeShortName) == "Link"
                    expect(bookmarks[4].routeID) == "40_100479"
                    expect(bookmarks[4].sortOrder) == Int.max
                    expect(bookmarks[4].tripHeadsign) == "University Of Washington Station"
                }

                done()
            }
        }
    }

    // MARK: - TestDelegate

    class TestDelegate: NSObject, DataMigrationDelegate {

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
