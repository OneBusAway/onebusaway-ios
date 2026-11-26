//
//  SheetCoordinatorTripPlannerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import MapKit
import OTPKit
@testable import OBAKit
@testable import OBAKitCore

/// Tests for `.tripPlanner` and `.mapItem` deduplication, singleton planner replacement,
/// and SwiftUI sheet identity across `SheetCoordinator` and `SheetRouteItem`.
@MainActor
@Suite(.serialized)
final class SheetCoordinatorTripPlannerTests {

    private func mapItem(latitude: Double, longitude: Double, name: String? = nil) -> MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))
        item.name = name
        return item
    }

    @Test func `Open trip planner with identical destination is a no-op when already on top`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let stop = AppSheetRoute.stopDetails(stopID: "stop_1")
        let firstPlanner = AppSheetRoute.tripPlanner(
            TripPlannerRequest(destination: mapItem(latitude: 47.6062, longitude: -122.3321, name: "Downtown"))
        )
        let duplicatePlanner = AppSheetRoute.tripPlanner(
            TripPlannerRequest(destination: mapItem(latitude: 47.6062, longitude: -122.3321, name: "Downtown Copy"))
        )

        coordinator.push(stop)
        coordinator.open(firstPlanner, from: stop)
        coordinator.setStackedDetent(.large, at: 1)

        coordinator.open(duplicatePlanner, from: stop)

        #expect(coordinator.stackedRoutes == [stop, firstPlanner])
        #expect(coordinator.stackedDetents == [.medium, .large])
        #expect(coordinator.unwindFocusDepth == nil)
    }

    @Test func `Open trip planner with identical destination unwinds when deeper in stack`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let firstPlanner = AppSheetRoute.tripPlanner(
            TripPlannerRequest(destination: mapItem(latitude: 47.6062, longitude: -122.3321))
        )
        let stop = AppSheetRoute.stopDetails(stopID: "stop_1")
        let duplicatePlanner = AppSheetRoute.tripPlanner(
            TripPlannerRequest(destination: mapItem(latitude: 47.6062, longitude: -122.3321))
        )

        coordinator.push(firstPlanner)
        coordinator.push(stop)

        coordinator.open(duplicatePlanner, from: stop)

        #expect(coordinator.stackedRoutes == [firstPlanner])
        #expect(coordinator.unwindFocusDepth == 1)
    }

    @Test func `Open trip planner replaces existing planner when transport mode or destination changes`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let stop = AppSheetRoute.stopDetails(stopID: "stop_1")
        let walkPlanner = AppSheetRoute.tripPlanner(
            TripPlannerRequest(destination: mapItem(latitude: 47.6062, longitude: -122.3321, name: "Seattle"), transportMode: .walk)
        )
        let bikePlanner = AppSheetRoute.tripPlanner(
            TripPlannerRequest(destination: mapItem(latitude: 47.6062, longitude: -122.3321, name: "Seattle"), transportMode: .bike)
        )
        let tacomaPlanner = AppSheetRoute.tripPlanner(
            TripPlannerRequest(destination: mapItem(latitude: 47.2529, longitude: -122.4443, name: "Tacoma"), transportMode: .transit)
        )

        // Switching transport modes from the same stop sheet replaces walk with bike instead of ignoring or stacking.
        coordinator.push(stop)
        coordinator.open(walkPlanner, from: stop)
        coordinator.open(bikePlanner, from: stop)
        #expect(coordinator.stackedRoutes == [stop, bikePlanner])

        // Opening a planner with a different destination replaces Seattle/bike with Tacoma instead of stacking two planners.
        coordinator.open(tacomaPlanner, from: stop)
        #expect(coordinator.stackedRoutes == [stop, tacomaPlanner])
    }

    @Test func `Open trip planner never stacks a second planner above a stop sheet above an existing planner`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let seattlePlanner = AppSheetRoute.tripPlanner(
            TripPlannerRequest(destination: mapItem(latitude: 47.6062, longitude: -122.3321, name: "Seattle"))
        )
        let stop = AppSheetRoute.stopDetails(stopID: "stop_1")
        let tacomaPlanner = AppSheetRoute.tripPlanner(
            TripPlannerRequest(destination: mapItem(latitude: 47.2529, longitude: -122.4443, name: "Tacoma"))
        )

        coordinator.push(seattlePlanner)
        coordinator.push(stop)

        // Only one planner may be open because both would share one TripPlannerMapDisplayModel.
        coordinator.open(tacomaPlanner, from: stop)
        #expect(coordinator.stackedRoutes == [tacomaPlanner])
    }

    @Test func `Restore route deduplicates repeated trip planner and map item selections`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let mapItemRoute1 = AppSheetRoute.mapItem(mapItem(latitude: 47.6062, longitude: -122.3321, name: "Pin A"))
        let mapItemRoute1Dup = AppSheetRoute.mapItem(mapItem(latitude: 47.6062, longitude: -122.3321, name: "Pin A Copy"))
        let mapItemRoute2 = AppSheetRoute.mapItem(mapItem(latitude: 47.6205, longitude: -122.3493, name: "Pin B"))
        let planner1 = AppSheetRoute.tripPlanner(
            TripPlannerRequest(destination: mapItem(latitude: 47.6062, longitude: -122.3321))
        )
        let planner1Dup = AppSheetRoute.tripPlanner(
            TripPlannerRequest(destination: mapItem(latitude: 47.6062, longitude: -122.3321))
        )
        let planner2 = AppSheetRoute.tripPlanner(
            TripPlannerRequest(destination: mapItem(latitude: 47.6205, longitude: -122.3493))
        )

        coordinator.restoreRoute(mapItemRoute1)
        coordinator.restoreRoute(mapItemRoute1Dup)
        #expect(coordinator.stackedRoutes == [mapItemRoute1])

        coordinator.restoreRoute(planner1)
        coordinator.restoreRoute(planner1Dup)
        #expect(coordinator.stackedRoutes == [mapItemRoute1, planner1])

        // A planner for a different destination replaces the active planner rather than stacking a second one.
        coordinator.restoreRoute(planner2)
        #expect(coordinator.stackedRoutes == [mapItemRoute1, planner2])

        // Restoring an earlier map item unwinds the planner above it.
        coordinator.restoreRoute(mapItemRoute1Dup)
        #expect(coordinator.stackedRoutes == [mapItemRoute1])

        // Selecting a different map item opens over the first.
        coordinator.selectFromMap(mapItemRoute2)
        #expect(coordinator.stackedRoutes == [mapItemRoute1, mapItemRoute2])
    }

    @Test func `SheetRouteItem distinguishes distinct trip planner payloads while keeping analytics id coordinate-free`() {
        let walk = AppSheetRoute.tripPlanner(
            TripPlannerRequest(destination: mapItem(latitude: 47.6062, longitude: -122.3321), transportMode: .walk)
        )
        let bike = AppSheetRoute.tripPlanner(
            TripPlannerRequest(destination: mapItem(latitude: 47.6062, longitude: -122.3321), transportMode: .bike)
        )
        let bikeCopy = AppSheetRoute.tripPlanner(
            TripPlannerRequest(destination: mapItem(latitude: 47.6062, longitude: -122.3321, name: "Copy"), transportMode: .bike)
        )

        // Analytics id stays payload-presence-only (no coordinates leaked),
        // while SheetRouteItem keys SwiftUI's .sheet(item:) on the full Route value.
        #expect(walk.id == "tripPlanner_destination_transportMode")
        #expect(walk.id == bike.id)
        #expect(SheetRouteItem(route: walk).id != SheetRouteItem(route: bike).id)
        #expect(SheetRouteItem(route: bike).id == SheetRouteItem(route: bikeCopy).id)
    }
}
