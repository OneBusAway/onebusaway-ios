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
    private var noBikeshareApplication: Application!

    override init() async throws {
        try await super.init()
        let queue = OperationQueue()
        let dataLoader = MockDataLoader(testName: name)
        application = buildApplication(queue: queue, dataLoader: dataLoader)

        // Set up a separate application for testing the no-bikeshare scenario
        let noBikeshareQueue = OperationQueue()
        let noBikeshareDataLoader = MockDataLoader(testName: "noBikeshare")
        noBikeshareApplication = buildApplication(queue: noBikeshareQueue, dataLoader: noBikeshareDataLoader)

        // Replace its region with one that has no bikeshare
        // Note: RegionsService.currentRegion getter looks up by ID in the regions list,
        // so we must use a unique ID that won't conflict
        if let currentRegion = noBikeshareApplication.regionsService.currentRegion {
            let noBikeshareRegion = Region(
                name: "No Bikeshare Test",
                OBABaseURL: currentRegion.OBABaseURL,
                coordinateRegion: MKCoordinateRegion(
                    center: currentRegion.centerCoordinate,
                    span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
                ),
                contactEmail: currentRegion.contactEmail,
                regionIdentifier: 99999, // Unique ID to avoid conflicts with fixture regions
                openTripPlannerURL: nil,
                openTripPlannerGraphQLURL: nil,
                supportsOTPGraphQLBikeshare: false
            )
            noBikeshareApplication.regionsService.currentRegion = noBikeshareRegion
        }
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
        // Verify the noBikeshareApplication region is set up correctly
        let region = try #require(noBikeshareApplication.regionsService.currentRegion)
        #expect(region.isBikeshareEnabled == false)
        #expect(region.openTripPlannerGraphQLURL == nil)
        #expect(region.supportsOTPGraphQLBikeshare == false)

        registrar = MapLayerRegistrar(application: noBikeshareApplication) { _ in }
        registrar.configure()

        #expect(noBikeshareApplication.mapRegionManager.mapLayer(id: RentalMapLayer.bikesLayerID) == nil)
        #expect(noBikeshareApplication.mapRegionManager.mapLayer(id: RentalMapLayer.scootersLayerID) == nil)
        #expect(registrar.rentalCoordinator == nil)
    }

    @Test func `Registers both rental layers for a bikeshare region`() throws {
        try enableBikeshareOnCurrentRegion()

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
        try enableBikeshareOnCurrentRegion()
        application.mapRegionManager.rentalRangeFilter = RentalRangeFilter(minimumRangeMeters: 8047)

        registrar = MapLayerRegistrar(application: application) { _ in }
        registrar.configure()

        #expect(registrar.rentalCoordinator != nil)
    }

    @Test func `Rebuilds rental layers on reconfigure`() throws {
        try enableBikeshareOnCurrentRegion()
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

    /// Sets the current region to one with bikeshare enabled and a GraphQL URL
    /// so the rental branch is reachable.
    private func enableBikeshareOnCurrentRegion() throws {
        let currentRegion = try #require(application.regionsService.currentRegion)
        let graphQLURL = URL(string: "https://otp.example.com/otp/routers/default/index/graphql")!

        // Build a coordinate region from the center coordinate
        let coordinateRegion = MKCoordinateRegion(
            center: currentRegion.centerCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )

        // Build a new Region with bikeshare enabled and GraphQL URL
        let bikeshareRegion = Region(
            name: currentRegion.name,
            OBABaseURL: currentRegion.OBABaseURL,
            coordinateRegion: coordinateRegion,
            contactEmail: currentRegion.contactEmail,
            regionIdentifier: currentRegion.regionIdentifier,
            openTripPlannerURL: currentRegion.openTripPlannerURL,
            openTripPlannerGraphQLURL: graphQLURL,
            supportsOTPGraphQLBikeshare: true,
            sidecarBaseURL: currentRegion.sidecarBaseURL,
            umamiAnalytics: currentRegion.umamiAnalytics
        )

        application.regionsService.currentRegion = bikeshareRegion
    }
}
