//
//  ResolvedRegionStoreTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class ResolvedRegionStoreTests: OBATestCase {

    @MainActor
    private func makeRegionsService(fileStorage: MockRegionsFileStorage) -> RegionsService {
        let locationService = LocationService(userDefaults: userDefaults, locationManager: LocationManagerMock())
        return RegionsService(
            apiService: nil,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: nil,
            fileStorage: fileStorage
        )
    }

    // MARK: - Store

    @Test func `Round trips a custom region, base URL included`() throws {
        let store = ResolvedRegionStore(userDefaults: userDefaults)
        let custom = Fixtures.customRegionWithSidecarAndUmami

        store.write(custom)
        let restored = try #require(store.region(bundledRegionsFilePath: nil))

        #expect(restored.regionIdentifier == custom.regionIdentifier)
        #expect(restored.OBABaseURL == custom.OBABaseURL)
        #expect(restored.name == custom.name)
    }

    @Test func `Writing nil clears the key`() {
        let store = ResolvedRegionStore(userDefaults: userDefaults)
        store.write(Fixtures.pugetSoundRegion)
        store.write(nil)

        #expect(userDefaults.object(forKey: ResolvedRegionStore.defaultsKey) == nil)
        #expect(store.region(bundledRegionsFilePath: nil) == nil)
    }

    /// The first widget reload after this ships happens before the app has
    /// launched and written anything.
    @Test func `Falls back to identifier lookup in the bundled regions when the key is absent`() throws {
        userDefaults.set(pugetSoundRegionIdentifier, forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)
        let store = ResolvedRegionStore(userDefaults: userDefaults)

        let region = try #require(store.region(bundledRegionsFilePath: bundledRegionsPath))
        #expect(region.regionIdentifier == pugetSoundRegionIdentifier)
    }

    @Test func `Fallback returns nil for an identifier the bundle does not know`() {
        userDefaults.set(987_654, forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)
        let store = ResolvedRegionStore(userDefaults: userDefaults)

        #expect(store.region(bundledRegionsFilePath: bundledRegionsPath) == nil)
    }

    @Test func `A corrupt stored value falls back instead of crashing`() throws {
        userDefaults.set(Data("not a plist".utf8), forKey: ResolvedRegionStore.defaultsKey)
        userDefaults.set(pugetSoundRegionIdentifier, forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)
        let store = ResolvedRegionStore(userDefaults: userDefaults)

        let region = try #require(store.region(bundledRegionsFilePath: bundledRegionsPath))
        #expect(region.regionIdentifier == pugetSoundRegionIdentifier)
    }

    // MARK: - Persister: the four triggers

    @Test @MainActor func `Trigger 1, launch: writes the current region on init`() throws {
        let service = makeRegionsService(fileStorage: MockRegionsFileStorage())
        service.currentRegion = try #require(service.find(id: pugetSoundRegionIdentifier))
        let store = ResolvedRegionStore(userDefaults: userDefaults)
        store.write(nil)

        let persister = ResolvedRegionPersister(regionsService: service, store: store)

        #expect(store.region(bundledRegionsFilePath: nil)?.regionIdentifier == pugetSoundRegionIdentifier)
        withExtendedLifetime(persister) {}
    }

    @Test @MainActor func `Trigger 2, updatedRegion: writes when the current region changes`() throws {
        let service = makeRegionsService(fileStorage: MockRegionsFileStorage())
        let store = ResolvedRegionStore(userDefaults: userDefaults)
        let persister = ResolvedRegionPersister(regionsService: service, store: store)

        let other = try #require(service.regions.first { $0.regionIdentifier != service.currentRegion?.regionIdentifier })
        service.currentRegion = other

        #expect(store.region(bundledRegionsFilePath: nil)?.regionIdentifier == other.regionIdentifier)
        withExtendedLifetime(persister) {}
    }

    /// The setter early-returns on an unchanged identifier, so a server-side
    /// edit to the current region arrives only as a list update.
    @Test @MainActor func `Trigger 3, updatedRegionsList: rewrites even though the identifier is unchanged`() throws {
        let service = makeRegionsService(fileStorage: MockRegionsFileStorage())
        service.currentRegion = try #require(service.find(id: pugetSoundRegionIdentifier))
        let store = ResolvedRegionStore(userDefaults: userDefaults)
        let persister = ResolvedRegionPersister(regionsService: service, store: store)

        store.write(nil)
        persister.regionsService(service, updatedRegionsList: service.regions)

        #expect(store.region(bundledRegionsFilePath: nil)?.regionIdentifier == pugetSoundRegionIdentifier)
    }

    @Test @MainActor func `Trigger 4, custom regions: editing the current custom region rewrites it`() async throws {
        let fileStorage = MockRegionsFileStorage()
        let service = makeRegionsService(fileStorage: fileStorage)
        let custom = Fixtures.customRegionWithSidecarAndUmami
        try await service.add(customRegion: custom)
        service.currentRegion = custom

        let store = ResolvedRegionStore(userDefaults: userDefaults)
        let persister = ResolvedRegionPersister(regionsService: service, store: store)
        store.write(nil)

        try await service.add(customRegion: custom)   // an edit: same identifier, replaces

        #expect(store.region(bundledRegionsFilePath: nil)?.regionIdentifier == custom.regionIdentifier)
        withExtendedLifetime(persister) {}
    }

    @Test @MainActor func `Clears the key when there is no current region`() {
        let service = makeRegionsService(fileStorage: MockRegionsFileStorage())
        userDefaults.removeObject(forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)
        let store = ResolvedRegionStore(userDefaults: userDefaults)
        store.write(Fixtures.pugetSoundRegion)

        let persister = ResolvedRegionPersister(regionsService: service, store: store)

        #expect(userDefaults.object(forKey: ResolvedRegionStore.defaultsKey) == nil)
        withExtendedLifetime(persister) {}
    }
}
