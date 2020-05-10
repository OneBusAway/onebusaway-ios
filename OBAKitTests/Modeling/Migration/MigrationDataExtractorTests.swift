//
//  MigrationDataExtractorTests.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 5/10/20.
//

import Foundation
import Nimble
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try syntactic_sugar

class MigrationDataExtractorTests: OBATestCase {

    var extractor: MigrationDataExtractor!

    override func setUp() {
        super.setUp()

        let testValues = try! Dictionary<String, Any>(plistPath: Fixtures.path(to: "migration_test_preferences.plist"))!
        userDefaults.register(defaults: testValues)
        extractor = MigrationDataExtractor(defaults: userDefaults)
    }

    func test_hasData() {
        expect(self.extractor.hasDataToMigrate) == true
    }

    func test_userID() {
        expect(self.extractor.oldUserID) == "B72C5F1A-B8E5-4FB3-A857-CAC6EAC86DE0"
    }

    func test_bookmarkGroups() {
        let groups = extractor.extractBookmarkGroups()!

        expect(groups.count) == 4

        let untitledGroup = groups[0]
        expect(untitledGroup.name).to(beNil())
        expect(untitledGroup.bookmarks.count) == 0

        let workGroup = groups[1]
        expect(workGroup.name) == "Work"
        expect(workGroup.bookmarks.count) == 1
        expect(workGroup.todayScreenVisible) == false
        expect(workGroup.open) == true
        expect(workGroup.uuid) == "E87AFBD5-6B61-4916-947F-458476ACBF98"
        expect(workGroup.sortOrder) == 1

        let bm = workGroup.bookmarks.first!
        expect(bm.name) == "10 to Work"
        expect(bm.stopID) == "1_11370"
        expect(bm.routeShortName) == "10"
        expect(bm.tripHeadsign) == "Downtown Seattle"
        expect(bm.routeID) == "1_100002"

        let homeGroup = groups[2]
        expect(homeGroup.name) == "Home"
        expect(homeGroup.bookmarks.count) == 1

        let mikaGroup = groups[3]
        expect(mikaGroup.name) == "Mika"
        expect(mikaGroup.bookmarks.count) == 2
    }

    func test_bookmarks() {
        let bookmarks = extractor.extractBookmarks()!

        expect(bookmarks.count) == 2

        let bm1 = bookmarks[0]
        expect(bm1.name) == "CHS Light Rail"
        expect(bm1.stopID) == "1_99610"
        expect(bm1.routeShortName) == "Link"
        expect(bm1.tripHeadsign) == "Beacon Hill"
        expect(bm1.routeID) == "40_100479"
    }

    func test_recentStops() {
        let recentStops = extractor.extractRecentStops()!

        expect(recentStops.count) == 6
    }

    func test_currentRegion() {
        let region = extractor.extractRegion()!

        expect(region.name) == "Puget Sound"
        expect(region.identifier) == 1
    }
}
