//
//  MapPanelOnDemandPlannerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import MapKit
import OTPKit
import SwiftUI
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// R11 in the map panel: an empty trip plan offers the on-demand services that
/// serve both ends, through the `TripPlanEmptyFallback` the classic map shares.
@MainActor
@Suite(.serialized)
final class MapPanelOnDemandPlannerTests: OBATestCase {

    private var application: Application!
    private var dataLoader: MockDataLoader!
    private var probeController: OnDemandProbeController!
    private var fallback: TripPlanEmptyFallback!
    private let notificationCenter = NotificationCenter()
    private let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)

    /// Tuesday 2026-03-10 15:09 EDT, when the fixture's Alexandria service runs.
    private let now = ISO8601DateFormatter().date(from: "2026-03-10T19:09:00Z")!
    /// Two ends inside Alexandria's zone, five decimals apart so each is probed.
    private let origin = CLLocationCoordinate2D(latitude: 38.8, longitude: -77.05)
    private let destination = CLLocationCoordinate2D(latitude: 38.81, longitude: -77.05)

    override init() async throws {
        try await super.init()
        dataLoader = MockDataLoader(testName: name)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.tampaRegion.OBABaseURL)
        application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)
        // A probe that finds services loads their geometry; nothing here draws it.
        dataLoader.mock(data: Data(), statusCode: 500) { $0.url?.path.contains("/api/ondemand/service/") ?? false }

        let now = self.now
        probeController = OnDemandProbeController(
            apiService: { [weak application] in application?.apiService },
            geometryCache: OnDemandGeometryCache { apiService, serviceID in
                try await apiService.getOnDemandService(id: serviceID, geometryDetail: .full).entry.areas
            },
            now: { now }
        )
        fallback = MapPanelOnDemandPlanner.makeFallback(probeController: probeController, notificationCenter: notificationCenter, coordinator: coordinator)
    }

    // MARK: - Helpers

    private func mockProbe() {
        dataLoader.mock(data: Fixtures.loadData(file: "ondemand_services_for_location_point.json")) {
            $0.url?.path.contains("/api/ondemand/services-for-location") ?? false
        }
    }

    /// Every probe from here on fails with a server error.
    private func failProbes() {
        dataLoader.replaceMappedResponses { staging in
            staging.mock(data: Data(), statusCode: 500) { $0.url?.path.contains("/api/ondemand/services-for-location") ?? false }
            staging.mock(data: Data(), statusCode: 500) { $0.url?.path.contains("/api/ondemand/service/") ?? false }
        }
    }

    private func mapItem(_ coordinate: CLLocationCoordinate2D) -> MKMapItem {
        MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
    }

    /// Opens the planner sheet the way the panel does, at `detent`.
    private func openPlanner(_ request: TripPlannerRequest = TripPlannerRequest(), at detent: PresentationDetent = .medium) {
        coordinator.push(.tripPlanner(request))
        coordinator.setStackedDetent(detent) { if case .tripPlanner = $0 { true } else { false } }
        MapPanelOnDemandPlanner.plannerDidChange(to: request, fallback: fallback, currentLocation: nil)
    }

    private func postEmptyPlan(from origin: CLLocationCoordinate2D?, to destination: CLLocationCoordinate2D?) {
        var userInfo: [AnyHashable: Any] = [Notifications.tripPlanEmptyReasonKey: Notifications.tripPlanEmptyReasonEmpty]
        if let origin, let destination {
            userInfo[Notifications.tripPlanEmptyOriginLatitudeKey] = origin.latitude
            userInfo[Notifications.tripPlanEmptyOriginLongitudeKey] = origin.longitude
            userInfo[Notifications.tripPlanEmptyDestinationLatitudeKey] = destination.latitude
            userInfo[Notifications.tripPlanEmptyDestinationLongitudeKey] = destination.longitude
        }
        notificationCenter.post(name: Notifications.tripPlanEmpty, object: nil, userInfo: userInfo)
    }

    private var plannerDetent: PresentationDetent? {
        MapPanelOnDemandPlanner.plannerEntry(in: coordinator.stackedEntries)?.detent
    }

    private var qualifyingIDs: [String]? {
        guard case .planner(let result) = probeController.dockState else { return nil }
        return result.qualifying.map(\.id)
    }

    /// An empty plan from `origin` to `destination` that ends with the card showing.
    private func showCard() async throws {
        postEmptyPlan(from: origin, to: destination)
        await fallback.task?.value
        try #require(qualifyingIDs == ["5088_77652"])
    }

    // MARK: - Showing the card

    @Test func `An empty plan with on-demand service at both ends shows the card above the planner`() async throws {
        mockProbe()
        openPlanner(at: .large)

        try await showCard()

        #expect(plannerDetent == .medium, "a full-height planner covers the card")
        let placement = MapPanelOnDemandPlanner.dockPlacement(
            dockState: probeController.dockState,
            plannerDetent: plannerDetent,
            sheetHeight: AppSheetRoute.homeCollapsedHeight,
            halfScreenHeight: 400,
            totalMapHeight: 800
        )
        #expect(placement.height == 400, "the card rides on the planner sheet, not the base sheet under it")
        #expect(placement.opacity == 1)
    }

    @Test func `A planner the rider lowered stays where it is`() async throws {
        mockProbe()
        openPlanner(at: .height(AppSheetRoute.tripPlannerTipHeight))

        try await showCard()

        #expect(plannerDetent == .height(AppSheetRoute.tripPlannerTipHeight))
    }

    @Test func `Without endpoints in the notification the planner's own are probed`() async throws {
        mockProbe()
        openPlanner(TripPlannerRequest(origin: mapItem(origin), destination: mapItem(destination)))

        postEmptyPlan(from: nil, to: nil)
        await fallback.task?.value

        #expect(qualifyingIDs == ["5088_77652"])
        let probedLatitudes = dataLoader.recordedRequestURLs
            .filter { $0.path.contains("/api/ondemand/services-for-location") }
            .compactMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "lat" }?.value }
            .compactMap(Double.init)
        #expect(Set(probedLatitudes) == [origin.latitude, destination.latitude])
    }

    // MARK: - Clearing the card

    @Test func `A failed probe shows nothing and clears an earlier card`() async throws {
        mockProbe()
        openPlanner()
        try await showCard()

        failProbes()
        postEmptyPlan(from: CLLocationCoordinate2D(latitude: 38.82, longitude: -77.05), to: destination)
        await fallback.task?.value

        #expect(probeController.dockState == .hidden)
    }

    @Test func `An empty plan with no endpoints at all clears an earlier card`() async throws {
        mockProbe()
        openPlanner()
        try await showCard()

        postEmptyPlan(from: nil, to: nil)

        #expect(probeController.dockState == .hidden)
        #expect(fallback.task == nil)
    }

    @Test func `A new plan with itineraries clears the card`() async throws {
        mockProbe()
        openPlanner()
        try await showCard()

        notificationCenter.post(name: Notifications.itinerariesUpdated, object: nil)

        #expect(probeController.dockState == .hidden)
    }

    @Test func `A re-plan cancels the earlier probe so its late answer can't show`() async throws {
        mockProbe()
        openPlanner()
        // Both ends answer from the cache, so the cancelled probe still gets a
        // result: only the fallback's own check keeps it off the screen.
        _ = await probeController.plannerResult(origin: origin, destination: destination)

        postEmptyPlan(from: origin, to: destination)
        let earlierProbe = try #require(fallback.task)
        notificationCenter.post(name: Notifications.itinerariesUpdated, object: nil)
        await earlierProbe.value

        #expect(probeController.dockState == .hidden)
    }

    @Test func `Closing the planner clears the card and stops listening`() async throws {
        mockProbe()
        openPlanner()
        try await showCard()

        coordinator.pop()
        MapPanelOnDemandPlanner.plannerDidChange(to: MapPanelOnDemandPlanner.plannerEntry(in: coordinator.stackedEntries)?.request, fallback: fallback, currentLocation: nil)
        #expect(probeController.dockState == .hidden)

        postEmptyPlan(from: origin, to: destination)
        #expect(fallback.task == nil, "a closed planner's notifications start nothing")
        #expect(probeController.dockState == .hidden)
    }

    // MARK: - Placement

    @Test func `The dock keeps the base sheet's placement unless a planner card is showing`() throws {
        let hidden = MapPanelOnDemandPlanner.dockPlacement(dockState: .hidden, plannerDetent: .medium, sheetHeight: 75, halfScreenHeight: 400, totalMapHeight: 800)
        #expect(hidden.height == 75)
        #expect(hidden.opacity == nil, "the toolbars' own fade applies")
    }

    @Test func `A planner card hides under a full-height planner`() async throws {
        mockProbe()
        let result = try #require(await probeController.plannerResult(origin: origin, destination: destination))

        let placement = MapPanelOnDemandPlanner.dockPlacement(dockState: .planner(result), plannerDetent: .large, sheetHeight: 75, halfScreenHeight: 400, totalMapHeight: 800)

        #expect(placement.opacity == 0)
    }
}
