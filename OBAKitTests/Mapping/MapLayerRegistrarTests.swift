//
//  MapLayerRegistrarTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// The registrar is the half of layer setup both map surfaces share. These
/// tests assert what it registers, not what any surface then draws.
@MainActor
@Suite(.serialized)
final class MapLayerRegistrarTests: OBATestCase {

    private var application: Application!
    private var registrar: MapLayerRegistrar!

    override init() async throws {
        try await super.init()
        let queue = OperationQueue()
        let dataLoader = MockDataLoader(testName: name)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        application = buildApplication(queue: queue, dataLoader: dataLoader)
    }

    @Test func `Registers the stops layer`() {
        registrar = MapLayerRegistrar(application: application) { _ in }
        registrar.configure()

        #expect(application.mapRegionManager.mapLayer(id: StopsMapLayer.layerID) != nil)
    }

    @Test func `Registering twice does not duplicate the stops layer`() {
        registrar = MapLayerRegistrar(application: application) { _ in }
        registrar.configure()
        registrar.configure()

        let stopsLayers = application.mapRegionManager.mapLayers.filter { $0.id == StopsMapLayer.layerID }
        #expect(stopsLayers.count == 1)
    }

    /// The region flag is product enablement and the GraphQL URL is the
    /// capability. Without both, there is no rental data source, so no rows.
    @Test func `Skips rental layers when the region has no bikeshare`() throws {
        let currentRegion = try #require(application.regionsService.currentRegion)

        // Create a region without bikeshare, using the same OBABaseURL so
        // existing agency stubs continue to work
        let noBikeshareRegion = Region(
            name: currentRegion.name,
            OBABaseURL: currentRegion.OBABaseURL,
            coordinateRegion: MKCoordinateRegion(
                center: currentRegion.centerCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
            ),
            contactEmail: currentRegion.contactEmail,
            regionIdentifier: 99999,
            openTripPlannerURL: nil,
            openTripPlannerGraphQLURL: nil,
            supportsOTPGraphQLBikeshare: false
        )

        application.regionsService.currentRegion = noBikeshareRegion

        registrar = MapLayerRegistrar(application: application) { _ in }
        registrar.configure()

        #expect(application.mapRegionManager.mapLayer(id: RentalMapLayer.bikesLayerID) == nil)
        #expect(application.mapRegionManager.mapLayer(id: RentalMapLayer.scootersLayerID) == nil)
        #expect(registrar.rentalCoordinator == nil)
    }

    @Test func `Registers both rental layers for a bikeshare region`() throws {
        let currentRegion = try #require(application.regionsService.currentRegion)

        // Build a bikeshare-enabled region using the same OBABaseURL so existing
        // agency stubs continue to work
        let bikeshareRegion = Region(
            name: currentRegion.name,
            OBABaseURL: currentRegion.OBABaseURL,
            coordinateRegion: MKCoordinateRegion(
                center: currentRegion.centerCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
            ),
            contactEmail: currentRegion.contactEmail,
            regionIdentifier: currentRegion.regionIdentifier,
            openTripPlannerURL: currentRegion.openTripPlannerURL,
            openTripPlannerGraphQLURL: URL(string: "https://otp.example.com/graphql"),
            supportsOTPGraphQLBikeshare: true,
            sidecarBaseURL: currentRegion.sidecarBaseURL,
            umamiAnalytics: currentRegion.umamiAnalytics
        )
        application.regionsService.currentRegion = bikeshareRegion

        registrar = MapLayerRegistrar(application: application) { _ in }
        registrar.configure()

        #expect(application.mapRegionManager.mapLayer(id: RentalMapLayer.bikesLayerID) != nil)
        #expect(application.mapRegionManager.mapLayer(id: RentalMapLayer.scootersLayerID) != nil)
        #expect(registrar.rentalCoordinator != nil)
        #expect(registrar.rentalLayers.count == 2)
    }

    /// A returning rider's stored threshold must reach the coordinator before
    /// the first fetch, not one notification later.
    @Test func `Applies the persisted range filter before the first fetch`() throws {
        let currentRegion = try #require(application.regionsService.currentRegion)

        // Build a bikeshare-enabled region using the same OBABaseURL
        let bikeshareRegion = Region(
            name: currentRegion.name,
            OBABaseURL: currentRegion.OBABaseURL,
            coordinateRegion: MKCoordinateRegion(
                center: currentRegion.centerCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
            ),
            contactEmail: currentRegion.contactEmail,
            regionIdentifier: currentRegion.regionIdentifier,
            openTripPlannerURL: currentRegion.openTripPlannerURL,
            openTripPlannerGraphQLURL: URL(string: "https://otp.example.com/graphql"),
            supportsOTPGraphQLBikeshare: true,
            sidecarBaseURL: currentRegion.sidecarBaseURL,
            umamiAnalytics: currentRegion.umamiAnalytics
        )
        application.regionsService.currentRegion = bikeshareRegion
        application.mapRegionManager.rentalRangeFilter = RentalRangeFilter(minimumRangeMeters: 8047)

        registrar = MapLayerRegistrar(application: application) { _ in }
        registrar.configure()

        #expect(registrar.rentalCoordinator != nil)
    }

    @Test func `Rebuilds rental layers on reconfigure`() throws {
        let currentRegion = try #require(application.regionsService.currentRegion)

        // Build a bikeshare-enabled region using the same OBABaseURL
        let bikeshareRegion = Region(
            name: currentRegion.name,
            OBABaseURL: currentRegion.OBABaseURL,
            coordinateRegion: MKCoordinateRegion(
                center: currentRegion.centerCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
            ),
            contactEmail: currentRegion.contactEmail,
            regionIdentifier: currentRegion.regionIdentifier,
            openTripPlannerURL: currentRegion.openTripPlannerURL,
            openTripPlannerGraphQLURL: URL(string: "https://otp.example.com/graphql"),
            supportsOTPGraphQLBikeshare: true,
            sidecarBaseURL: currentRegion.sidecarBaseURL,
            umamiAnalytics: currentRegion.umamiAnalytics
        )
        application.regionsService.currentRegion = bikeshareRegion

        registrar = MapLayerRegistrar(application: application) { _ in }
        registrar.configure()
        let first = try #require(registrar.rentalCoordinator)

        registrar.configure()
        let second = try #require(registrar.rentalCoordinator)

        #expect(first !== second)
    }

    @Test func `Notifies the host after configuring`() throws {
        var callCount = 0
        registrar = MapLayerRegistrar(application: application) { _ in callCount += 1 }

        registrar.configure()

        #expect(callCount == 1)
    }
}
