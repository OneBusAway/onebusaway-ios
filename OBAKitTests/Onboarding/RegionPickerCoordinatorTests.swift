//
//  RegionPickerCoordinatorTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Tests for `RegionPickerCoordinator`, the `ObservableObject` the region picker
/// reads `RegionsService` through.
///
/// Changes made on the service reach the coordinator as delegate callbacks, and
/// each callback applies its change in a `Task { @MainActor in }`. The tests
/// drive the real service rather than calling those callbacks by hand, so the
/// coordinator's delegate registration is covered too.
@MainActor
@Suite(.serialized)
final class RegionPickerCoordinatorTests: OBATestCase {

    private var store: UserDefaultsStore!

    override init() async throws {
        try await super.init()
        store = UserDefaultsStore(userDefaults: userDefaults)
    }

    /// A service with the bundled regions, no stored selection, and (by default)
    /// no location, so nothing selects a region until a test does.
    private func makeService(locationManager: LocationManager = LocationManagerMock()) -> RegionsService {
        RegionsService(
            apiService: regionsAPIService,
            locationService: LocationService(userDefaults: userDefaults, locationManager: locationManager),
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: regionsAPIPath,
            fileStorage: MockRegionsFileStorage()
        )
    }

    private func makeCoordinator(_ service: RegionsService) -> RegionPickerCoordinator {
        RegionPickerCoordinator(regionsService: service, userDataStore: store)
    }

    /// Lets the coordinator's pending delegate callbacks run. Each one is a
    /// `Task { @MainActor in }`, and the main actor runs its jobs in the order
    /// they were enqueued, so once a task enqueued after them has finished, they
    /// have finished too.
    private func drainMainActor() async {
        await Task { @MainActor in }.value
    }

    // MARK: - Custom regions

    @Test func `Adding a custom region makes it current and turns off automatic selection`() async throws {
        let service = makeService()
        let coordinator = makeCoordinator(service)
        #expect(coordinator.currentRegion == nil)
        #expect(coordinator.automaticallySelectRegion)

        let custom = Fixtures.customMinneapolisRegion
        try await coordinator.add(customRegion: custom)
        await drainMainActor()

        #expect(service.currentRegion?.regionIdentifier == custom.regionIdentifier)
        #expect(coordinator.currentRegion?.regionIdentifier == custom.regionIdentifier)
        #expect(coordinator.automaticallySelectRegion == false)
        #expect(service.automaticallySelectRegion == false)
    }

    /// `RegionsService` reports custom regions through a delegate method the
    /// coordinator doesn't implement, so only `add` itself can update the list.
    @Test func `Adding a custom region lists it after the known regions`() async throws {
        let coordinator = makeCoordinator(makeService())
        let countBefore = coordinator.allRegions.count

        let custom = Fixtures.customMinneapolisRegion
        try await coordinator.add(customRegion: custom)

        #expect(coordinator.allRegions.count == countBefore + 1)
        #expect(coordinator.allRegions.last?.regionIdentifier == custom.regionIdentifier)
    }

    @Test func `Deleting a custom region removes it from the list`() async throws {
        let service = makeService()
        let coordinator = makeCoordinator(service)
        let countBefore = coordinator.allRegions.count

        let custom = Fixtures.customMinneapolisRegion
        try await coordinator.add(customRegion: custom)
        // The service refuses to delete the current region, and adding made it current.
        try await coordinator.setCurrentRegion(to: try #require(service.regions.first))
        #expect(coordinator.allRegions.contains { $0.regionIdentifier == custom.regionIdentifier })

        try await coordinator.delete(customRegion: custom)

        #expect(coordinator.allRegions.contains { $0.regionIdentifier == custom.regionIdentifier } == false)
        #expect(coordinator.allRegions.count == countBefore)
    }

    // MARK: - Current region

    @Test func `Choosing a region in the picker selects it in the regions service`() async throws {
        let service = makeService()
        let coordinator = makeCoordinator(service)
        let region = try #require(service.regions.last)
        #expect(service.currentRegion == nil)

        try await coordinator.setCurrentRegion(to: region)

        #expect(service.currentRegion?.regionIdentifier == region.regionIdentifier)
    }

    @Test func `A region selected on the service becomes the picker's current region`() async throws {
        let service = makeService()
        let coordinator = makeCoordinator(service)
        let region = try #require(service.regions.first)
        #expect(coordinator.currentRegion == nil)

        service.currentRegion = region
        await drainMainActor()

        #expect(coordinator.currentRegion?.regionIdentifier == region.regionIdentifier)
    }

    // MARK: - Region list

    @Test func `Refreshed regions replace the picker's list`() async throws {
        stubRegions(dataLoader: try #require(regionsAPIService.dataLoader as? MockDataLoader))
        let service = makeService()
        let coordinator = makeCoordinator(service)
        let refreshedIDs = try Fixtures.loadSomeRegions().map(\.regionIdentifier)
        // The bundled list differs from the fixture, or this test proves nothing.
        #expect(coordinator.allRegions.map(\.regionIdentifier) != refreshedIDs)

        try await service.refreshRegions()
        await drainMainActor()

        #expect(coordinator.allRegions.map(\.regionIdentifier) == refreshedIDs)
    }

    // MARK: - Automatic selection

    @Test func `Turning off automatic selection on the service turns it off in the picker`() async {
        let service = makeService()
        let coordinator = makeCoordinator(service)
        #expect(coordinator.automaticallySelectRegion)

        service.automaticallySelectRegion = false
        await drainMainActor()

        #expect(coordinator.automaticallySelectRegion == false)
    }

    @Test func `Turning off automatic selection in the picker turns it off in the service`() {
        let service = makeService()
        let coordinator = makeCoordinator(service)
        #expect(service.automaticallySelectRegion)

        coordinator.automaticallySelectRegion = false

        #expect(service.automaticallySelectRegion == false)
    }

    /// The rider's location arriving outside every region is what makes the real
    /// service give up on automatic selection.
    @Test func `Failing to find a region for the rider turns off automatic selection`() async throws {
        let midPacific = CLLocation(latitude: 0, longitude: -160)
        let locationManager = MockAuthorizedLocationManager(updateLocation: midPacific, updateHeading: TestData.mockHeading)
        let service = makeService(locationManager: locationManager)
        let coordinator = makeCoordinator(service)
        #expect(service.allRegions.contains { $0.contains(location: midPacific) } == false)
        #expect(coordinator.automaticallySelectRegion)

        locationManager.location = midPacific
        await drainMainActor()

        #expect(service.currentRegion == nil)
        #expect(coordinator.automaticallySelectRegion == false)
        #expect(service.automaticallySelectRegion == false)
    }

    // MARK: - Trip planning

    @Test func `Trip planning is kept per region in the injected store`() throws {
        let coordinator = makeCoordinator(makeService())
        let regions = try Fixtures.loadSomeRegions()
        let tampa = regions[0], pugetSound = regions[1]

        coordinator.setTripPlanningEnabled(false, for: tampa)
        #expect(store.isTripPlanningEnabled(for: tampa) == false)
        #expect(coordinator.isTripPlanningEnabled(for: pugetSound))

        store.setTripPlanningEnabled(false, for: pugetSound)
        #expect(coordinator.isTripPlanningEnabled(for: pugetSound) == false)
        #expect(coordinator.isTripPlanningEnabled(for: tampa) == false)
    }
}
