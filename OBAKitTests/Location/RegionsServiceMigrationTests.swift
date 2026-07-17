//
//  RegionsServiceMigrationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import XCTest
@testable import OBAKitCore

/// Tests for the one-time migration of region data from UserDefaults to disk storage.
///
/// Every user upgrading from a pre-disk-storage release runs this migration exactly once
/// at launch, so these tests guard against losing the user's selected region, the
/// downloaded region list, or their custom regions during an app update.
class RegionsServiceMigrationTests: OBATestCase {

    private var fileStorage: MockRegionsFileStorage!

    override func setUp() async throws {
        try await super.setUp()
        fileStorage = MockRegionsFileStorage()
    }

    private enum TestError: Error {
        case diskWriteFailed
    }

    private func encode<T: Encodable>(_ value: T) -> Data {
        // Force-try is safe: these are static test fixtures, so a failure here
        // is a test-authoring bug that should crash immediately rather than be handled.
        try! PropertyListEncoder().encode(value)
    }

    private func migrate() {
        RegionsService.migrateFromUserDefaultsIfNeeded(userDefaults: userDefaults, fileStorage: fileStorage)
    }

    // MARK: - No Legacy Data

    func test_noLegacyData_isANoOp() {
        migrate()

        XCTAssertNil(fileStorage.storedDefaultRegions)
        XCTAssertTrue(fileStorage.storedCustomRegions.isEmpty)
        XCTAssertNil(userDefaults.object(forKey: RegionsService.currentRegionIdentifierUserDefaultsKey))
    }

    // MARK: - Default Regions

    func test_defaultRegions_migratedToDiskAndLegacyKeyRemoved() {
        let regions = [Fixtures.pugetSoundRegion, Fixtures.tampaRegion]
        userDefaults.set(encode(regions), forKey: RegionsService.legacyStoredRegionsUserDefaultsKey)

        migrate()

        XCTAssertEqual(fileStorage.storedDefaultRegions?.map(\.regionIdentifier), regions.map(\.regionIdentifier))
        XCTAssertNil(userDefaults.data(forKey: RegionsService.legacyStoredRegionsUserDefaultsKey))
    }

    func test_defaultRegions_corruptedData_isDiscardedAndKeyRemoved() {
        userDefaults.set(Data([0x00, 0x01, 0x02]), forKey: RegionsService.legacyStoredRegionsUserDefaultsKey)

        migrate()

        XCTAssertNil(fileStorage.storedDefaultRegions)
        XCTAssertNil(userDefaults.data(forKey: RegionsService.legacyStoredRegionsUserDefaultsKey))
    }

    func test_defaultRegions_emptyList_clearsKeyWithoutWriting() {
        userDefaults.set(encode([Region]()), forKey: RegionsService.legacyStoredRegionsUserDefaultsKey)

        migrate()

        XCTAssertNil(fileStorage.storedDefaultRegions)
        XCTAssertNil(userDefaults.data(forKey: RegionsService.legacyStoredRegionsUserDefaultsKey))
    }

    func test_defaultRegions_diskWriteFails_keyIsKeptForRetry() {
        let regions = [Fixtures.pugetSoundRegion]
        userDefaults.set(encode(regions), forKey: RegionsService.legacyStoredRegionsUserDefaultsKey)
        fileStorage.saveDefaultRegionsError = TestError.diskWriteFailed

        migrate()

        XCTAssertNotNil(userDefaults.data(forKey: RegionsService.legacyStoredRegionsUserDefaultsKey),
                        "A failed disk write must leave the legacy key intact so migration retries on next launch")

        // Next launch: the disk write succeeds and the key is cleared.
        fileStorage.saveDefaultRegionsError = nil
        migrate()

        XCTAssertEqual(fileStorage.storedDefaultRegions?.count, 1)
        XCTAssertNil(userDefaults.data(forKey: RegionsService.legacyStoredRegionsUserDefaultsKey))
    }

    // MARK: - Custom Regions

    func test_customRegions_migratedToDiskAndLegacyKeyRemoved() {
        let regions = [Fixtures.customMinneapolisRegion]
        userDefaults.set(encode(regions), forKey: RegionsService.legacyStoredCustomRegionsUserDefaultsKey)

        migrate()

        XCTAssertEqual(fileStorage.storedCustomRegions.map(\.regionIdentifier), regions.map(\.regionIdentifier))
        XCTAssertNil(userDefaults.data(forKey: RegionsService.legacyStoredCustomRegionsUserDefaultsKey))
    }

    func test_customRegions_corruptedData_isDiscardedAndKeyRemoved() {
        userDefaults.set(Data([0xFF]), forKey: RegionsService.legacyStoredCustomRegionsUserDefaultsKey)

        migrate()

        XCTAssertTrue(fileStorage.storedCustomRegions.isEmpty)
        XCTAssertNil(userDefaults.data(forKey: RegionsService.legacyStoredCustomRegionsUserDefaultsKey))
    }

    func test_customRegions_saveFails_keyIsKeptForRetry() {
        let regions = [Fixtures.customMinneapolisRegion]
        userDefaults.set(encode(regions), forKey: RegionsService.legacyStoredCustomRegionsUserDefaultsKey)
        fileStorage.saveCustomRegionError = TestError.diskWriteFailed

        migrate()

        XCTAssertNotNil(userDefaults.data(forKey: RegionsService.legacyStoredCustomRegionsUserDefaultsKey),
                        "A failed save must leave the legacy key intact so migration retries on next launch")

        fileStorage.saveCustomRegionError = nil
        migrate()

        XCTAssertEqual(fileStorage.storedCustomRegions.count, 1)
        XCTAssertNil(userDefaults.data(forKey: RegionsService.legacyStoredCustomRegionsUserDefaultsKey))
    }

    // MARK: - Current Region

    func test_currentRegion_convertedToIdentifierAndLegacyKeyRemoved() {
        let region = Fixtures.pugetSoundRegion
        userDefaults.set(encode(region), forKey: RegionsService.legacyCurrentRegionUserDefaultsKey)

        migrate()

        XCTAssertEqual(
            userDefaults.object(forKey: RegionsService.currentRegionIdentifierUserDefaultsKey) as? Int,
            region.regionIdentifier
        )
        XCTAssertNil(userDefaults.data(forKey: RegionsService.legacyCurrentRegionUserDefaultsKey))
    }

    func test_currentRegion_corruptedData_isDiscardedAndKeyRemoved() {
        userDefaults.set(Data([0x42]), forKey: RegionsService.legacyCurrentRegionUserDefaultsKey)

        migrate()

        XCTAssertNil(userDefaults.object(forKey: RegionsService.currentRegionIdentifierUserDefaultsKey))
        XCTAssertNil(userDefaults.data(forKey: RegionsService.legacyCurrentRegionUserDefaultsKey))
    }

    // MARK: - Idempotency

    func test_fullMigration_isIdempotent() {
        userDefaults.set(encode([Fixtures.pugetSoundRegion]), forKey: RegionsService.legacyStoredRegionsUserDefaultsKey)
        userDefaults.set(encode([Fixtures.customMinneapolisRegion]), forKey: RegionsService.legacyStoredCustomRegionsUserDefaultsKey)
        userDefaults.set(encode(Fixtures.pugetSoundRegion), forKey: RegionsService.legacyCurrentRegionUserDefaultsKey)

        migrate()
        let defaultsAfterFirstRun = fileStorage.storedDefaultRegions
        let customAfterFirstRun = fileStorage.storedCustomRegions

        migrate()

        XCTAssertEqual(fileStorage.storedDefaultRegions?.map(\.regionIdentifier), defaultsAfterFirstRun?.map(\.regionIdentifier))
        XCTAssertEqual(fileStorage.storedCustomRegions.map(\.regionIdentifier), customAfterFirstRun.map(\.regionIdentifier))
        XCTAssertEqual(
            userDefaults.object(forKey: RegionsService.currentRegionIdentifierUserDefaultsKey) as? Int,
            Fixtures.pugetSoundRegion.regionIdentifier
        )
    }
}
