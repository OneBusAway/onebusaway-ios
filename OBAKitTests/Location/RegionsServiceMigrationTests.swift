//
//  RegionsServiceMigrationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

/// Tests for the one-time migration of region data from UserDefaults to disk storage.
///
/// Every user upgrading from a pre-disk-storage release runs this migration exactly once
/// at launch, so these tests guard against losing the user's selected region, the
/// downloaded region list, or their custom regions during an app update.
@Suite(.serialized)
final class RegionsServiceMigrationTests: OBATestCase {

    private var fileStorage: MockRegionsFileStorage!

    override init() async throws {
        try await super.init()

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

    @Test func `No legacy data is a no op`() {
        migrate()

        #expect(fileStorage.storedDefaultRegions == nil)
        #expect(fileStorage.storedCustomRegions.isEmpty)
        #expect(userDefaults.object(forKey: RegionsService.currentRegionIdentifierUserDefaultsKey) == nil)
    }

    // MARK: - Default Regions

    @Test func `Default regions migrated to disk and legacy key removed`() {
        let regions = [Fixtures.pugetSoundRegion, Fixtures.tampaRegion]
        userDefaults.set(encode(regions), forKey: RegionsService.legacyStoredRegionsUserDefaultsKey)

        migrate()

        #expect(fileStorage.storedDefaultRegions?.map(\.regionIdentifier) == regions.map(\.regionIdentifier))
        #expect(userDefaults.data(forKey: RegionsService.legacyStoredRegionsUserDefaultsKey) == nil)
    }

    @Test func `Default regions corrupted data is discarded and key removed`() {
        userDefaults.set(Data([0x00, 0x01, 0x02]), forKey: RegionsService.legacyStoredRegionsUserDefaultsKey)

        migrate()

        #expect(fileStorage.storedDefaultRegions == nil)
        #expect(userDefaults.data(forKey: RegionsService.legacyStoredRegionsUserDefaultsKey) == nil)
    }

    @Test func `Default regions empty list clears key without writing`() {
        userDefaults.set(encode([Region]()), forKey: RegionsService.legacyStoredRegionsUserDefaultsKey)

        migrate()

        #expect(fileStorage.storedDefaultRegions == nil)
        #expect(userDefaults.data(forKey: RegionsService.legacyStoredRegionsUserDefaultsKey) == nil)
    }

    @Test func `Default regions disk write fails key is kept for retry`() {
        let regions = [Fixtures.pugetSoundRegion]
        userDefaults.set(encode(regions), forKey: RegionsService.legacyStoredRegionsUserDefaultsKey)
        fileStorage.saveDefaultRegionsError = TestError.diskWriteFailed

        migrate()

        #expect(userDefaults.data(forKey: RegionsService.legacyStoredRegionsUserDefaultsKey) != nil, "A failed disk write must leave the legacy key intact so migration retries on next launch")

        // Next launch: the disk write succeeds and the key is cleared.
        fileStorage.saveDefaultRegionsError = nil
        migrate()

        #expect(fileStorage.storedDefaultRegions?.count == 1)
        #expect(userDefaults.data(forKey: RegionsService.legacyStoredRegionsUserDefaultsKey) == nil)
    }

    // MARK: - Custom Regions

    @Test func `Custom regions migrated to disk and legacy key removed`() {
        let regions = [Fixtures.customMinneapolisRegion]
        userDefaults.set(encode(regions), forKey: RegionsService.legacyStoredCustomRegionsUserDefaultsKey)

        migrate()

        #expect(fileStorage.storedCustomRegions.map(\.regionIdentifier) == regions.map(\.regionIdentifier))
        #expect(userDefaults.data(forKey: RegionsService.legacyStoredCustomRegionsUserDefaultsKey) == nil)
    }

    @Test func `Custom regions corrupted data is discarded and key removed`() {
        userDefaults.set(Data([0xFF]), forKey: RegionsService.legacyStoredCustomRegionsUserDefaultsKey)

        migrate()

        #expect(fileStorage.storedCustomRegions.isEmpty)
        #expect(userDefaults.data(forKey: RegionsService.legacyStoredCustomRegionsUserDefaultsKey) == nil)
    }

    @Test func `Custom regions save fails key is kept for retry`() {
        let regions = [Fixtures.customMinneapolisRegion]
        userDefaults.set(encode(regions), forKey: RegionsService.legacyStoredCustomRegionsUserDefaultsKey)
        fileStorage.saveCustomRegionError = TestError.diskWriteFailed

        migrate()

        #expect(userDefaults.data(forKey: RegionsService.legacyStoredCustomRegionsUserDefaultsKey) != nil, "A failed save must leave the legacy key intact so migration retries on next launch")

        fileStorage.saveCustomRegionError = nil
        migrate()

        #expect(fileStorage.storedCustomRegions.count == 1)
        #expect(userDefaults.data(forKey: RegionsService.legacyStoredCustomRegionsUserDefaultsKey) == nil)
    }

    // MARK: - Current Region

    @Test func `Current region converted to identifier and legacy key removed`() {
        let region = Fixtures.pugetSoundRegion
        userDefaults.set(encode(region), forKey: RegionsService.legacyCurrentRegionUserDefaultsKey)

        migrate()

        #expect((userDefaults.object(forKey: RegionsService.currentRegionIdentifierUserDefaultsKey) as? Int) == region.regionIdentifier)
        #expect(userDefaults.data(forKey: RegionsService.legacyCurrentRegionUserDefaultsKey) == nil)
    }

    @Test func `Current region corrupted data is discarded and key removed`() {
        userDefaults.set(Data([0x42]), forKey: RegionsService.legacyCurrentRegionUserDefaultsKey)

        migrate()

        #expect(userDefaults.object(forKey: RegionsService.currentRegionIdentifierUserDefaultsKey) == nil)
        #expect(userDefaults.data(forKey: RegionsService.legacyCurrentRegionUserDefaultsKey) == nil)
    }

    // MARK: - Idempotency

    @Test func `Full migration is idempotent`() {
        userDefaults.set(encode([Fixtures.pugetSoundRegion]), forKey: RegionsService.legacyStoredRegionsUserDefaultsKey)
        userDefaults.set(encode([Fixtures.customMinneapolisRegion]), forKey: RegionsService.legacyStoredCustomRegionsUserDefaultsKey)
        userDefaults.set(encode(Fixtures.pugetSoundRegion), forKey: RegionsService.legacyCurrentRegionUserDefaultsKey)

        migrate()
        let defaultsAfterFirstRun = fileStorage.storedDefaultRegions
        let customAfterFirstRun = fileStorage.storedCustomRegions

        migrate()

        #expect(fileStorage.storedDefaultRegions?.map(\.regionIdentifier) == defaultsAfterFirstRun?.map(\.regionIdentifier))
        #expect(fileStorage.storedCustomRegions.map(\.regionIdentifier) == customAfterFirstRun.map(\.regionIdentifier))
        #expect((userDefaults.object(forKey: RegionsService.currentRegionIdentifierUserDefaultsKey) as? Int) == Fixtures.pugetSoundRegion.regionIdentifier)
    }
}
