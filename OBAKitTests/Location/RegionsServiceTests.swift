//
//  RegionsServiceTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore
import CoreLocation

// swiftlint:disable file_length
// swiftlint:disable:next weak_delegate
private class RegionsServiceTestDelegate: NSObject, RegionsServiceDelegate {
    private(set) var unableToSelectRegion: DelegateTestingHelper.DidCallDelegateMethod<Void> = .didNotCall
    private(set) var updatedRegionsList: DelegateTestingHelper.DidCallDelegateMethod<[Region]> = .didNotCall
    private(set) var willUpdateToRegion: DelegateTestingHelper.DidCallDelegateMethod<Region> = .didNotCall
    private(set) var newRegionSelected: DelegateTestingHelper.DidCallDelegateMethod<Region> = .didNotCall
    private(set) var allUpdatedRegions: [Region] = []
    private(set) var regionUpdateCancelled: DelegateTestingHelper.DidCallDelegateMethod<Void> = .didNotCall
    private(set) var displayedError: DelegateTestingHelper.DidCallDelegateMethod<Error> = .didNotCall

    func regionsServiceUnableToSelectRegion(_ service: RegionsService) {
        unableToSelectRegion = .called(Void())
    }

    func regionsService(_ service: RegionsService, updatedRegionsList regions: [Region]) {
        updatedRegionsList = .called(regions)
    }

    func regionsService(_ service: RegionsService, willUpdateToRegion region: Region) {
        willUpdateToRegion = .called(region)
    }

    func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        newRegionSelected = .called(region)
        allUpdatedRegions.append(region)
    }

    func regionsServiceListUpdateCancelled(_ service: RegionsService) {
        regionUpdateCancelled = .called(Void())
    }

    func regionsService(_ service: RegionsService, displayError error: Error) {
        displayedError = .called(error)
    }
}

// MARK: - Test Case

@Suite(.serialized)
final class RegionsServiceTests: OBATestCase {
    private var testDelegate: RegionsServiceTestDelegate!
    var locationManagerMock: LocationManagerMock!
    var locationService: LocationService!
    var dataLoader: MockDataLoader!
    var mockFileStorage: MockRegionsFileStorage!

    override init() async throws {
        try await super.init()

        testDelegate = RegionsServiceTestDelegate()
        locationManagerMock = LocationManagerMock()
        locationService = LocationService(userDefaults: UserDefaults(), locationManager: locationManagerMock)
        guard let mockDataLoader = regionsAPIService.dataLoader as? MockDataLoader else {
            fatalError("Expected MockDataLoader")
        }
        dataLoader = mockDataLoader
        mockFileStorage = MockRegionsFileStorage()
    }

    // MARK: - Convenience builder

    private func makeRegionsService(delegate: RegionsServiceTestDelegate? = nil) -> RegionsService {
        RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: regionsPath,
            fileStorage: mockFileStorage,
            delegate: delegate
        )
    }

    // MARK: - Upon creating the Regions Service

    // It loads bundled regions from its framework when no other data exists
    @Test func `Init loads bundled regions`() {
        stubRegions(dataLoader: dataLoader)

        let service = makeRegionsService()
        #expect(service.regions.count == 7)
    }

    // It loads regions saved to disk when they exist
    @Test func `Init loads saved regions`() throws {
        stubRegions(dataLoader: dataLoader)

        let customRegion = Fixtures.customMinneapolisRegion
        mockFileStorage.storedDefaultRegions = [customRegion]

        let service = makeRegionsService()

        let firstRegion = try #require(service.regions.first)
        #expect(firstRegion.name == "Custom Region", "Expected the first region to be the custom region")
        #expect(service.regions.count == 1)
    }

    // It loads the current region identifier from user defaults when it exists (auto-select disabled)
    @Test func `Init loads current region auto select disabled`() throws {
        stubRegions(dataLoader: dataLoader)

        let customRegion = Fixtures.customMinneapolisRegion
        mockFileStorage.storedDefaultRegions = [customRegion]
        userDefaults.set(false, forKey: RegionsService.automaticallySelectRegionUserDefaultsKey)
        userDefaults.set(customRegion.regionIdentifier, forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)

        let service = makeRegionsService()

        #expect(service.currentRegion == customRegion)
    }

    @Test func `Init loads current region auto select enabled`() throws {
        stubRegions(dataLoader: dataLoader)

        // Store the Minneapolis region identifier, but location points to Puget Sound —
        // auto-select should override and pick Puget Sound.
        let minneapolis = Fixtures.customMinneapolisRegion
        userDefaults.set(minneapolis.regionIdentifier, forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)
        locationManagerMock.location = CLLocation(latitude: 47.632445, longitude: -122.312607)

        let service = makeRegionsService()

        let currentRegion = try #require(service.currentRegion)
        #expect(currentRegion.name == "Puget Sound")
    }

    /// It downloads an up-to-date list of regions if that list hasn't been updated in at least a week.
    @Test func `Init update regions list`() async {
        stubRegionsJustPugetSound(dataLoader: dataLoader)

        let regionsService = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: regionsAPIPath,
            fileStorage: mockFileStorage,
            delegate: testDelegate
        )

        await regionsService.updateRegionsList()

        #expect(testDelegate.updatedRegionsList.didCall, "Expected RegionsService to inform delegates that the regionsList was updated")
    }

    /// It *does not* download a list of regions if the list was last updated less than a week ago.
    @Test func `Init skip update regions list`() async {
        stubRegionsJustPugetSound(dataLoader: dataLoader)
        userDefaults.set(Date(), forKey: RegionsService.regionsUpdatedAtUserDefaultsKey)

        let regionsService = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: regionsAPIPath,
            fileStorage: mockFileStorage,
            delegate: testDelegate
        )

        await regionsService.updateRegionsList()

        #expect(testDelegate.regionUpdateCancelled.didCall, "Expected RegionsService to inform delegates that the region update was cancelled")
        #expect(regionsService.regions.count == 7)
    }

    /// It *does* download a list of regions—even if the list was last updated less than a week ago—if the update is forced.
    @Test func `Init force update regions list`() async {
        stubRegionsJustPugetSound(dataLoader: dataLoader)
        userDefaults.set(Date(), forKey: RegionsService.regionsUpdatedAtUserDefaultsKey)

        let regionsService = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: regionsAPIPath,
            fileStorage: mockFileStorage,
            delegate: testDelegate
        )

        await regionsService.updateRegionsList(forceUpdate: true)
        #expect(!testDelegate.regionUpdateCancelled.didCall, "Expected RegionsService to not inform delegates that a region update was cancelled")
        #expect(testDelegate.updatedRegionsList.didCall, "Expected RegionsService to inform delegates that the regionsList was updated")
        #expect(regionsService.regions.count == 1)
    }

    /// It *does* download a list of regions—even if the list was last updated less than a week ago—if alwaysRefreshRegionsOnLaunchUserDefaultsKey is true.
    @Test func `Init always refresh regions on launch`() async {
        stubRegionsJustPugetSound(dataLoader: dataLoader)
        userDefaults.set(Date(), forKey: RegionsService.regionsUpdatedAtUserDefaultsKey)
        userDefaults.set(true, forKey: RegionsService.alwaysRefreshRegionsOnLaunchUserDefaultsKey)

        let regionsService = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: regionsAPIPath,
            fileStorage: mockFileStorage,
            delegate: testDelegate
        )

        await regionsService.updateRegionsList()
        #expect(testDelegate.updatedRegionsList.didCall, "Expected RegionsService to inform delegates that the regionsList was updated")
        #expect(regionsService.regions.count == 1)
    }

    // MARK: - Persistence

    // It stores downloaded region data in file storage when the regions property is set.
    @Test func persistence() async throws {
        stubRegionsJustPugetSound(dataLoader: dataLoader)
        userDefaults.set(Date(), forKey: RegionsService.regionsUpdatedAtUserDefaultsKey)

        let regionsService = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: regionsAPIPath,
            fileStorage: mockFileStorage,
            delegate: testDelegate
        )

        await regionsService.updateRegionsList(forceUpdate: true)
        #expect(testDelegate.updatedRegionsList.didCall)

        // Verify regions were saved to file storage (not UserDefaults).
        let regions = try #require(mockFileStorage.storedDefaultRegions, "Expected regions to be saved to file storage")

        #expect(regions.count == 1)
        #expect(regions.first?.name == "Puget Sound")
    }

    /// It loads the bundled regions when file storage returns an error (e.g. corrupted data).
    @Test func `Corrupted storage`() {
        stubRegions(dataLoader: dataLoader)

        mockFileStorage.loadDefaultRegionsError = CocoaError(.fileReadCorruptFile)

        let regionsService = makeRegionsService()

        #expect(regionsService.regions.count == 7)
    }

    /// It calls delegates to tell them that the current region is updated when that property is written.
    @Test func `Region updated notifications`() {
        stubRegions(dataLoader: dataLoader)

        let regionsService = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: regionsAPIPath,
            fileStorage: mockFileStorage,
            delegate: testDelegate
        )

        let newRegion = Fixtures.customMinneapolisRegion
        // Put the region in file storage so it can be looked up by identifier.
        mockFileStorage.storedCustomRegions = [newRegion]

        regionsService.currentRegion = newRegion

        expectDidCallDelegateMethod(testDelegate.newRegionSelected, newRegion, "Expected RegionsService to inform delegates of the new region selection")
        #expect(regionsService.currentRegion == newRegion, "Expected RegionsService to update its currentRegion property to the new region")
    }

    /// It notifies delegates when registering a custom region if that region matches the stored identifier.
    @Test func `Region updated notifications when previously nil but stored identifier matches`() throws {
        stubRegions(dataLoader: dataLoader)

        let newRegion = Fixtures.customMinneapolisRegion
        userDefaults.set(newRegion.regionIdentifier, forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)

        let regionsService = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: regionsAPIPath,
            fileStorage: mockFileStorage,
            delegate: testDelegate
        )

        // Storage does not contain custom region yet, so currentRegion is nil.
        #expect(regionsService.currentRegion == nil)

        // Registering the custom region resolves the stored identifier and notifies delegates.
        try regionsService.registerCustomRegionIfNeeded(newRegion)

        expectDidCallDelegateMethod(testDelegate.newRegionSelected, newRegion, "Expected RegionsService to inform delegates of region selection when registered custom region matches stored identifier")
        #expect(regionsService.currentRegion == newRegion)
    }

    @Test func `registerCustomRegionIfNeeded saves custom region and makes it discoverable`() throws {
        stubRegions(dataLoader: dataLoader)

        let regionsService = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: regionsAPIPath,
            fileStorage: mockFileStorage,
            delegate: testDelegate
        )

        let newRegion = Fixtures.customMinneapolisRegion
        #expect(regionsService.find(id: newRegion.regionIdentifier) == nil)

        try regionsService.registerCustomRegionIfNeeded(newRegion)

        #expect(regionsService.find(id: newRegion.regionIdentifier) == newRegion)
        #expect(mockFileStorage.storedCustomRegions.contains(where: { $0.regionIdentifier == newRegion.regionIdentifier }))
    }

    // MARK: - Network Data

    // It updates the 'last updated at' date in user defaults when the regions list is downloaded.
    @Test func `Region list updated updated at date is written`() async throws {
        stubRegionsJustPugetSound(dataLoader: dataLoader)
        userDefaults.set(Date.distantPast, forKey: RegionsService.regionsUpdatedAtUserDefaultsKey)

        let regionsService = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: regionsAPIPath,
            fileStorage: mockFileStorage,
            delegate: testDelegate
        )

        await regionsService.updateRegionsList()
        #expect(testDelegate.updatedRegionsList.didCall, "Expected RegionsService to inform delegates that the regionsList was updated")

        let newDate = try #require(userDefaults.value(forKey: RegionsService.regionsUpdatedAtUserDefaultsKey) as? Date, "Expected \(RegionsService.regionsUpdatedAtUserDefaultsKey) to be of type Date")

        let interval = newDate.timeIntervalSince(.now)
        expectClose(interval, 0.0, within: 2.0, "Expected the regionsUpdatedAt time to be near the current time")
        #expect(regionsService.regions.first?.name == "Puget Sound", "Expected a region to exist in the regionsService")
    }

    /// The list is refreshed once a day. The distance is taken either way, so a
    /// last update stamped in the future (the clock was set back) also refreshes.
    @Test(arguments: [(hoursFromNow: -23.0, refreshes: false), (hoursFromNow: -25.0, refreshes: true), (hoursFromNow: 48.0, refreshes: true)])
    func `Region list refreshes only when its last update is a day or more from now`(hoursFromNow: Double, refreshes: Bool) async {
        stubRegionsJustPugetSound(dataLoader: dataLoader)
        userDefaults.set(Date(timeIntervalSinceNow: hoursFromNow * 3600), forKey: RegionsService.regionsUpdatedAtUserDefaultsKey)
        let regionsService = makeRegionsService(delegate: testDelegate)

        await regionsService.updateRegionsList()

        #expect(testDelegate.updatedRegionsList.didCall == refreshes)
        #expect(testDelegate.regionUpdateCancelled.didCall == !refreshes)
        #expect(regionsService.regions.count == (refreshes ? 1 : 7))
    }

    @Test func `A failed region list refresh reports the error and keeps the old list and currentRegion`() async throws {
        let path = regionsAPIPath
        dataLoader.mock(data: Data(), statusCode: 500) { $0.url?.path == path }
        let regionsService = makeRegionsService(delegate: testDelegate)
        let initialRegion = try #require(regionsService.regions.first)
        regionsService.currentRegion = initialRegion

        await regionsService.updateRegionsList(forceUpdate: true)

        guard case .called(let error) = testDelegate.displayedError,
              case .requestFailure(let response)? = error as? APIError else {
            Issue.record("Expected the 500 to reach delegates as APIError.requestFailure, got \(testDelegate.displayedError)")
            return
        }
        #expect(response.statusCode == 500)
        #expect(regionsService.regions.count == 7)
        #expect(regionsService.currentRegion?.regionIdentifier == initialRegion.regionIdentifier)
        #expect(!testDelegate.updatedRegionsList.didCall)
        #expect(regionsService.lastRefreshFailed)
    }

    @Test func `Network connection failure sets lastRefreshFailed and preserves existing regions and currentRegion`() async throws {
        let path = regionsAPIPath
        let mockResponse = MockDataResponse(
            data: nil,
            urlResponse: nil,
            error: URLError(.notConnectedToInternet),
            matcher: { $0.url?.path == path }
        )
        dataLoader.mock(response: mockResponse)
        let regionsService = makeRegionsService(delegate: testDelegate)
        let initialRegion = try #require(regionsService.regions.first)
        regionsService.currentRegion = initialRegion

        await regionsService.updateRegionsList(forceUpdate: true)

        #expect(regionsService.lastRefreshFailed)
        #expect(regionsService.regions.count == 7)
        #expect(regionsService.currentRegion?.regionIdentifier == initialRegion.regionIdentifier)
        #expect(!testDelegate.updatedRegionsList.didCall)
        #expect(testDelegate.displayedError.didCall)
    }

    /// An empty list from the server must not wipe the regions the app already has.
    @Test func `An empty region list from the server keeps the stored regions`() async {
        let emptyList = Data(#"{"version": 3, "code": 200, "text": "OK", "data": {"list": []}}"#.utf8)
        let path = regionsAPIPath
        dataLoader.mock(data: emptyList) { $0.url?.path == path }
        let regionsService = makeRegionsService(delegate: testDelegate)

        await regionsService.updateRegionsList(forceUpdate: true)

        #expect(regionsService.regions.count == 7)
        #expect(!testDelegate.updatedRegionsList.didCall)
        #expect(testDelegate.displayedError.didCall == false)
    }

    @Test func `Successful refresh resets lastRefreshFailed`() async {
        let path = regionsAPIPath
        dataLoader.mock(data: Data(), statusCode: 500) { $0.url?.path == path }
        let regionsService = makeRegionsService(delegate: testDelegate)
        #expect(!regionsService.lastRefreshFailed)

        await regionsService.updateRegionsList(forceUpdate: true)
        #expect(regionsService.lastRefreshFailed)

        // Then succeed
        dataLoader.removeMappedResponses()
        stubRegionsJustPugetSound(dataLoader: dataLoader)
        await regionsService.updateRegionsList(forceUpdate: true)
        #expect(!regionsService.lastRefreshFailed)
    }

    @Test func `Recovery after failed refresh syncs regions list, resolves pending region, clears failure flag, and notifies delegates`() async throws {
        let pugetSound = try #require(Fixtures.loadSomeRegions().first(where: { $0.name == "Puget Sound" }))
        // User has Puget Sound stored, but default regions in storage is empty and bundle doesn't have it
        userDefaults.set(pugetSound.regionIdentifier, forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)
        userDefaults.set(false, forKey: RegionsService.automaticallySelectRegionUserDefaultsKey)

        // Stub empty bundle by using a temp file
        let emptyJSON = Data(#"{"version": 3, "code": 200, "text": "OK", "data": {"list": []}}"#.utf8)
        let tempBundle = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try emptyJSON.write(to: tempBundle, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tempBundle) }

        // Initial refresh fails with server 500
        let path = regionsAPIPath
        dataLoader.mock(data: Data(), statusCode: 500) { $0.url?.path == path }

        let regionsService = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: tempBundle.path,
            apiPath: regionsAPIPath,
            fileStorage: mockFileStorage,
            delegate: testDelegate
        )

        #expect(regionsService.currentRegion == nil)
        #expect(!regionsService.lastRefreshFailed)
        #expect(!testDelegate.newRegionSelected.didCall)
        #expect(!testDelegate.willUpdateToRegion.didCall)

        await regionsService.updateRegionsList(forceUpdate: true)

        #expect(regionsService.lastRefreshFailed)
        #expect(regionsService.currentRegion == nil)
        #expect(!testDelegate.newRegionSelected.didCall)
        #expect(!testDelegate.willUpdateToRegion.didCall)

        // Recovery: subsequent sync succeeds with Puget Sound
        dataLoader.removeMappedResponses()
        stubRegionsJustPugetSound(dataLoader: dataLoader)

        await regionsService.updateRegionsList(forceUpdate: true)

        #expect(!regionsService.lastRefreshFailed)
        #expect(regionsService.regions.count == 1)
        #expect(regionsService.currentRegion?.regionIdentifier == pugetSound.regionIdentifier)
        #expect(testDelegate.updatedRegionsList.didCall)
        #expect(testDelegate.newRegionSelected.didCall)
        #expect(testDelegate.willUpdateToRegion.didCall)
        if case .called(let notifiedRegion) = testDelegate.newRegionSelected {
            #expect(notifiedRegion.regionIdentifier == pugetSound.regionIdentifier)
        }
        if case .called(let willRegion) = testDelegate.willUpdateToRegion {
            #expect(willRegion.regionIdentifier == pugetSound.regionIdentifier)
        }
    }

    @Test func `Recovery does not notify stale captured region if current identifier changed during refresh`() async throws {
        let allRegions = try Fixtures.loadSomeRegions()
        let pugetSound = try #require(allRegions.first(where: { $0.name == "Puget Sound" }))
        let tampa = try #require(allRegions.first(where: { $0.name == "Tampa Bay" }))

        // User initially has Puget Sound stored, but default regions in storage is empty and bundle doesn't have it.
        userDefaults.set(pugetSound.regionIdentifier, forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)
        userDefaults.set(true, forKey: RegionsService.automaticallySelectRegionUserDefaultsKey)

        // User is physically located in Tampa Bay.
        locationManagerMock.location = TestData.mockTampaLocation

        // Stub empty bundle by using a temp file so Puget Sound is initially unresolved.
        let emptyJSON = Data(#"{"version": 3, "code": 200, "text": "OK", "data": {"list": []}}"#.utf8)
        let tempBundle = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try emptyJSON.write(to: tempBundle, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tempBundle) }

        stubRegions(dataLoader: dataLoader)

        let regionsService = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: tempBundle.path,
            apiPath: regionsAPIPath,
            fileStorage: mockFileStorage,
            delegate: testDelegate
        )

        #expect(regionsService.currentRegion == nil)
        #expect(testDelegate.allUpdatedRegions.isEmpty)

        await regionsService.updateRegionsList(forceUpdate: true)

        // Tampa should be selected from location via regions.didSet,
        // and recovery branch must NOT notify delegates for the stale Puget Sound identifier.
        #expect(regionsService.currentRegion?.regionIdentifier == tampa.regionIdentifier)
        #expect(testDelegate.allUpdatedRegions.count == 1)
        #expect(testDelegate.allUpdatedRegions.first?.regionIdentifier == tampa.regionIdentifier)
        if case .called(let notifiedRegion) = testDelegate.newRegionSelected {
            #expect(notifiedRegion.regionIdentifier == tampa.regionIdentifier)
        }
    }

    @Test func `Fallback resolution recovers currentRegion from ResolvedRegionStore when unresolved in regions`() throws {
        let pugetSound = try #require(Fixtures.loadSomeRegions().first(where: { $0.name == "Puget Sound" }))
        userDefaults.set(pugetSound.regionIdentifier, forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)

        // Empty bundle
        let emptyJSON = Data(#"{"version": 3, "code": 200, "text": "OK", "data": {"list": []}}"#.utf8)
        let tempBundle = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try emptyJSON.write(to: tempBundle, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tempBundle) }

        // Store Puget Sound in ResolvedRegionStore
        let store = ResolvedRegionStore(userDefaults: userDefaults)
        store.write(pugetSound)

        let regionsService = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: tempBundle.path,
            apiPath: regionsAPIPath,
            fileStorage: mockFileStorage
        )

        // Puget Sound is NOT in regions or customRegions
        #expect(regionsService.find(id: pugetSound.regionIdentifier) == nil)
        // But currentRegion resolves via ResolvedRegionStore fallback
        #expect(regionsService.currentRegion?.regionIdentifier == pugetSound.regionIdentifier)
    }

    @Test func `Stale bundle missing stored region preserves user intent via ResolvedRegionStore and ignores location auto-select`() throws {
        let tampa = try #require(Fixtures.loadSomeRegions().first(where: { $0.name == "Tampa Bay" }))
        let pugetSound = try #require(Fixtures.loadSomeRegions().first(where: { $0.name == "Puget Sound" }))

        userDefaults.set(tampa.regionIdentifier, forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)
        userDefaults.set(false, forKey: RegionsService.automaticallySelectRegionUserDefaultsKey)

        let store = ResolvedRegionStore(userDefaults: userDefaults)
        store.write(tampa)

        // Stale bundle contains only Puget Sound (Tampa is missing from bundle)
        let staleBundlePath = Fixtures.path(to: "regions-just-puget-sound.json")

        // GPS location is physically in Puget Sound
        let seattleLocation = CLLocation(latitude: 47.632445, longitude: -122.312607)
        locationManagerMock.location = seattleLocation

        let regionsService = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: staleBundlePath,
            apiPath: regionsAPIPath,
            fileStorage: mockFileStorage,
            delegate: testDelegate
        )

        // Stale bundle does not have Tampa in regions list
        #expect(regionsService.find(id: tampa.regionIdentifier) == nil)
        #expect(regionsService.regions.contains(where: { $0.regionIdentifier == pugetSound.regionIdentifier }))

        // Preserved via ResolvedRegionStore fallback
        #expect(regionsService.currentRegion?.regionIdentifier == tampa.regionIdentifier)
        #expect(userDefaults.integer(forKey: RegionsService.currentRegionIdentifierUserDefaultsKey) == tampa.regionIdentifier)

        // Auto-select by location does not overwrite user intent
        regionsService.locationService(locationService, locationChanged: seattleLocation)
        #expect(regionsService.currentRegion?.regionIdentifier == tampa.regionIdentifier)
        #expect(userDefaults.integer(forKey: RegionsService.currentRegionIdentifierUserDefaultsKey) == tampa.regionIdentifier)
    }

    @Test func `Offline launch with stored selection does not clobber intent on location or fixed region`() throws {
        let tampa = try #require(Fixtures.loadSomeRegions().first(where: { $0.name == "Tampa Bay" }))
        userDefaults.set(tampa.regionIdentifier, forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)
        userDefaults.set(false, forKey: RegionsService.automaticallySelectRegionUserDefaultsKey)

        // Location points to Puget Sound
        locationManagerMock.location = CLLocation(latitude: 47.632445, longitude: -122.312607)

        // Empty bundle so regions does not have Tampa
        let emptyJSON = Data(#"{"version": 3, "code": 200, "text": "OK", "data": {"list": []}}"#.utf8)
        let tempBundle = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try emptyJSON.write(to: tempBundle, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tempBundle) }

        // Seed file storage with single active region (Puget Sound)
        let pugetSound = try #require(Fixtures.loadSomeRegions().first(where: { $0.name == "Puget Sound" }))
        mockFileStorage.storedDefaultRegions = [pugetSound]

        _ = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: tempBundle.path,
            apiPath: regionsAPIPath,
            fileStorage: mockFileStorage,
            fixedRegionName: "Puget Sound"
        )

        // Stored identifier must remain Tampa
        #expect(userDefaults.integer(forKey: RegionsService.currentRegionIdentifierUserDefaultsKey) == tampa.regionIdentifier)
    }

    @Test func `Offline launch preserves currentRegion, GPS fix does not clobber selection, and cached bookmarks remain accessible`() throws {
        let tampa = try #require(Fixtures.loadSomeRegions().first(where: { $0.name == "Tampa Bay" }))
        let pugetSound = try #require(Fixtures.loadSomeRegions().first(where: { $0.name == "Puget Sound" }))

        userDefaults.set(tampa.regionIdentifier, forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)
        userDefaults.set(false, forKey: RegionsService.automaticallySelectRegionUserDefaultsKey)

        let store = ResolvedRegionStore(userDefaults: userDefaults)
        store.write(tampa)

        let userStore = UserDefaultsStore(userDefaults: userDefaults)
        let stops = try Fixtures.loadSomeStops()
        let tampaBookmark = Bookmark(name: "Tampa Work", regionIdentifier: tampa.regionIdentifier, stop: stops[0])
        let psBookmark = Bookmark(name: "Seattle Home", regionIdentifier: pugetSound.regionIdentifier, stop: stops[1])
        userStore.add(tampaBookmark, to: nil)
        userStore.add(psBookmark, to: nil)

        let emptyJSON = Data(#"{"version": 3, "code": 200, "text": "OK", "data": {"list": []}}"#.utf8)
        let tempBundle = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try emptyJSON.write(to: tempBundle, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tempBundle) }

        let seattleLocation = CLLocation(latitude: 47.632445, longitude: -122.312607)
        locationManagerMock.location = seattleLocation

        let regionsService = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: tempBundle.path,
            apiPath: regionsAPIPath,
            fileStorage: mockFileStorage,
            delegate: testDelegate
        )

        // 1. currentRegion is preserved via ResolvedRegionStore fallback
        #expect(regionsService.currentRegion?.regionIdentifier == tampa.regionIdentifier)
        #expect(userDefaults.integer(forKey: RegionsService.currentRegionIdentifierUserDefaultsKey) == tampa.regionIdentifier)

        // 2. GPS location fix does NOT clobber user's stored selection
        regionsService.locationService(locationService, locationChanged: seattleLocation)
        #expect(regionsService.currentRegion?.regionIdentifier == tampa.regionIdentifier)
        #expect(userDefaults.integer(forKey: RegionsService.currentRegionIdentifierUserDefaultsKey) == tampa.regionIdentifier)

        // 3. Cached bookmarks for currentRegion remain accessible
        let accessibleBookmarks = userStore.findBookmarks(in: regionsService.currentRegion)
        #expect(accessibleBookmarks.count == 1)
        #expect(accessibleBookmarks.first?.name == "Tampa Work")
        #expect(accessibleBookmarks.first?.regionIdentifier == tampa.regionIdentifier)
    }

    // MARK: - Custom Regions

    /// A failed read is not cached, so the custom regions come back once the
    /// file can be read again rather than staying empty for the session.
    @Test func `A failed custom regions read is retried on the next access`() {
        stubRegions(dataLoader: dataLoader)
        let custom = Fixtures.customMinneapolisRegion
        mockFileStorage.storedCustomRegions = [custom]
        mockFileStorage.loadCustomRegionsError = CocoaError(.fileReadCorruptFile)
        let regionsService = makeRegionsService()

        #expect(regionsService.customRegions.isEmpty)

        mockFileStorage.loadCustomRegionsError = nil
        #expect(regionsService.customRegions == [custom])
    }

    @Test func `Deleting the selected custom region throws and keeps it`() async {
        stubRegions(dataLoader: dataLoader)
        let custom = Fixtures.customMinneapolisRegion
        mockFileStorage.storedCustomRegions = [custom]
        let regionsService = makeRegionsService()
        regionsService.currentRegion = custom
        #expect(regionsService.currentRegion == custom)

        await #expect(throws: UnstructuredError.self) {
            try await regionsService.delete(customRegion: custom)
        }

        #expect(mockFileStorage.storedCustomRegions == [custom])
        #expect(regionsService.find(id: custom.regionIdentifier) == custom)
    }

    // MARK: - Migration

    /// It migrates downloaded regions from UserDefaults to disk storage on first launch.
    @Test func `Migration default regions`() throws {
        stubRegions(dataLoader: dataLoader)

        let customRegion = Fixtures.customMinneapolisRegion
        let plistData = try PropertyListEncoder().encode([customRegion])
        userDefaults.set(plistData, forKey: RegionsService.legacyStoredRegionsUserDefaultsKey)

        _ = makeRegionsService()

        // After init, the region should have been migrated to file storage.
        let migratedRegions = try #require(mockFileStorage.storedDefaultRegions, "Expected regions to be migrated to file storage")
        #expect(migratedRegions.count == 1)
        #expect(migratedRegions.first?.name == "Custom Region")

        // Legacy UserDefaults key should be cleared.
        #expect(userDefaults.data(forKey: RegionsService.legacyStoredRegionsUserDefaultsKey) == nil, "Expected legacy UserDefaults key to be cleared after migration")
    }

    /// It migrates custom regions from UserDefaults to individual disk files on first launch.
    @Test func `Migration custom regions`() throws {
        stubRegions(dataLoader: dataLoader)

        let customRegion = Fixtures.customMinneapolisRegion
        let plistData = try PropertyListEncoder().encode([customRegion])
        userDefaults.set(plistData, forKey: RegionsService.legacyStoredCustomRegionsUserDefaultsKey)

        _ = makeRegionsService()

        #expect(mockFileStorage.storedCustomRegions.count == 1)
        #expect(mockFileStorage.storedCustomRegions.first?.name == "Custom Region")

        #expect(userDefaults.data(forKey: RegionsService.legacyStoredCustomRegionsUserDefaultsKey) == nil, "Expected legacy custom regions key to be cleared after migration")
    }

    /// It migrates the current region from a full Region object to just the identifier.
    @Test func `Migration current region`() throws {
        stubRegions(dataLoader: dataLoader)

        let customRegion = Fixtures.customMinneapolisRegion
        let plistData = try PropertyListEncoder().encode(customRegion)
        userDefaults.set(plistData, forKey: RegionsService.legacyCurrentRegionUserDefaultsKey)

        _ = makeRegionsService()

        let migratedIdentifier = userDefaults.integer(forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)
        #expect(migratedIdentifier == customRegion.regionIdentifier, "Expected current region identifier to be migrated")

        #expect(userDefaults.data(forKey: RegionsService.legacyCurrentRegionUserDefaultsKey) == nil, "Expected legacy current region key to be cleared after migration")
    }

    /// Corrupt plist in the legacy default-regions key must be discarded (key cleared) without saving anything to disk.
    @Test func `Migration default regions corrupt data discards key`() {
        stubRegions(dataLoader: dataLoader)

        let data = Data("corrupted data".utf8)
        userDefaults.set(data, forKey: RegionsService.legacyStoredRegionsUserDefaultsKey)

        _ = makeRegionsService()

        #expect(userDefaults.data(forKey: RegionsService.legacyStoredRegionsUserDefaultsKey) == nil, "Corrupt legacy data should be discarded — the key must be cleared so migration does not retry on bad data")
        #expect(mockFileStorage.storedDefaultRegions == nil, "Nothing should be written to file storage when the legacy data is undecodable")
    }

    /// An empty region list in the legacy key must clear the key without touching file storage.
    @Test func `Migration default regions empty array clears key without saving`() throws {
        stubRegions(dataLoader: dataLoader)

        let plistData = try PropertyListEncoder().encode([Region]())
        userDefaults.set(plistData, forKey: RegionsService.legacyStoredRegionsUserDefaultsKey)

        _ = makeRegionsService()

        #expect(userDefaults.data(forKey: RegionsService.legacyStoredRegionsUserDefaultsKey) == nil, "An empty legacy region array should clear the key")
        #expect(mockFileStorage.storedDefaultRegions == nil, "Nothing should be written to file storage for an empty region list")
    }

    /// Corrupt plist in the legacy custom-regions key must be discarded (key cleared).
    @Test func `Migration custom regions corrupt data discards key`() {
        stubRegions(dataLoader: dataLoader)

        let data = Data("corrupted data".utf8)
        userDefaults.set(data, forKey: RegionsService.legacyStoredCustomRegionsUserDefaultsKey)

        _ = makeRegionsService()

        #expect(userDefaults.data(forKey: RegionsService.legacyStoredCustomRegionsUserDefaultsKey) == nil, "Corrupt legacy custom-region data should be discarded — key must be cleared")
        #expect(mockFileStorage.storedCustomRegions.isEmpty, "Nothing should be written to file storage when the legacy data is undecodable")
    }

    /// When any `saveCustomRegion` throws during migration the legacy key must be preserved for retry.
    @Test func `Migration custom regions save failure preserves legacy key`() throws {
        stubRegions(dataLoader: dataLoader)

        let customRegion = Fixtures.customMinneapolisRegion
        let plistData = try PropertyListEncoder().encode([customRegion])
        userDefaults.set(plistData, forKey: RegionsService.legacyStoredCustomRegionsUserDefaultsKey)

        mockFileStorage.saveCustomRegionError = CocoaError(.fileWriteNoPermission)

        _ = makeRegionsService()

        let preservedData = userDefaults.data(forKey: RegionsService.legacyStoredCustomRegionsUserDefaultsKey)
        #expect(preservedData != nil, "Legacy custom-regions key must NOT be deleted when saveCustomRegion throws — data would be lost permanently")
        #expect(preservedData == plistData, "Preserved legacy data must be byte-for-byte identical to the original")
        #expect(mockFileStorage.storedCustomRegions.isEmpty, "No custom regions should be stored when the save threw an error")
    }

    /// Corrupt plist in the legacy current-region key must be discarded via defer and must not
    /// write any identifier — unlike the default/custom cases this path does not retry on next launch.
    @Test func `Migration current region corrupt data clears key without writing identifier`() {
        stubRegions(dataLoader: dataLoader)

        let data = Data("corrupted data".utf8)
        userDefaults.set(data, forKey: RegionsService.legacyCurrentRegionUserDefaultsKey)

        _ = makeRegionsService()

        #expect(userDefaults.data(forKey: RegionsService.legacyCurrentRegionUserDefaultsKey) == nil, "Corrupt legacy current-region data should be cleared — there is nothing to retry")
        #expect(userDefaults.object(forKey: RegionsService.currentRegionIdentifierUserDefaultsKey) == nil, "No region identifier should be written when the legacy current-region data is undecodable")
    }

    /// When `saveDefaultRegions` throws during migration the legacy UserDefaults key must not be deleted
    /// — preserving the data so the migration can retry on the next launch.
    @Test func `Migration default regions save failure preserves legacy key`() throws {
        stubRegions(dataLoader: dataLoader)

        let customRegion = Fixtures.customMinneapolisRegion
        let plistData = try PropertyListEncoder().encode([customRegion])
        userDefaults.set(plistData, forKey: RegionsService.legacyStoredRegionsUserDefaultsKey)

        // Simulate a disk-write failure during migration.
        mockFileStorage.saveDefaultRegionsError = CocoaError(.fileWriteNoPermission)

        _ = makeRegionsService()

        // The legacy key must still be present with its original data intact so the migration retries on next launch.
        let preservedData = userDefaults.data(forKey: RegionsService.legacyStoredRegionsUserDefaultsKey)
        #expect(preservedData != nil, "Legacy UserDefaults key must NOT be deleted when saveDefaultRegions throws — data would be lost permanently")
        #expect(preservedData == plistData, "Preserved legacy data must be byte-for-byte identical to the original")

        // Nothing should have been written to file storage.
        #expect(mockFileStorage.storedDefaultRegions == nil, "No regions should be stored in file storage when the save threw an error")
    }

    // MARK: - Location Services

    /// Locations arrive through `LocationService`, the way the app gets them.
    @Test func `Moving into another region makes it the current region`() throws {
        stubRegions(dataLoader: dataLoader)
        locationManagerMock.location = TestData.mockSeattleLocation
        let regionsService = makeRegionsService(delegate: testDelegate)
        #expect(regionsService.currentRegion?.name == "Puget Sound")

        locationManagerMock.location = TestData.mockTampaLocation

        let tampa = try #require(regionsService.regions.first { $0.name == "Tampa Bay" })
        #expect(regionsService.currentRegion == tampa)
        expectDidCallDelegateMethod(testDelegate.newRegionSelected, tampa)
    }

    @Test func `With automatic selection off the current region stays until it is turned back on`() {
        stubRegions(dataLoader: dataLoader)
        locationManagerMock.location = TestData.mockSeattleLocation
        let regionsService = makeRegionsService(delegate: testDelegate)
        regionsService.automaticallySelectRegion = false

        locationManagerMock.location = TestData.mockTampaLocation
        #expect(regionsService.currentRegion?.name == "Puget Sound")

        regionsService.automaticallySelectRegion = true
        #expect(regionsService.currentRegion?.name == "Tampa Bay")
    }

    @Test func `A location outside every region asks delegates to pick one and keeps the current region`() {
        stubRegions(dataLoader: dataLoader)
        locationManagerMock.location = TestData.mockSeattleLocation
        let regionsService = makeRegionsService(delegate: testDelegate)
        #expect(!testDelegate.unableToSelectRegion.didCall)

        // The Gulf of Guinea, far from every bundled region.
        locationManagerMock.location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            altitude: 0, horizontalAccuracy: 10, verticalAccuracy: 10, timestamp: Date()
        )

        #expect(testDelegate.unableToSelectRegion.didCall)
        #expect(regionsService.currentRegion?.name == "Puget Sound")
    }

    @Test func `Without a location the current region is left alone and delegates are not asked to pick one`() {
        stubRegions(dataLoader: dataLoader)
        let regionsService = makeRegionsService(delegate: testDelegate)

        regionsService.updateCurrentRegionFromLocation()

        #expect(!testDelegate.unableToSelectRegion.didCall)
        #expect(regionsService.currentRegion == nil)
    }
}
