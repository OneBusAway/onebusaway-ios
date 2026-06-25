//
//  SheetCoordinatorTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
@testable import OBAKit

/// Behavior tests for `SheetCoordinator`'s content-swap and stacked navigation,
/// using `AppSheetRoute` as the concrete `SheetRouteable` driver.
@MainActor
final class SheetCoordinatorTests: XCTestCase {

    // MARK: - Init

    func test_init_seedsRouteStackWithRoot() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        expect(coordinator.routeStack.count) == 1
        expect(coordinator.currentRoute) == .home
        expect(coordinator.canPop) == false
    }

    func test_init_setsCurrentDetentToRootInitialDetent() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        expect(coordinator.currentDetent) == AppSheetRoute.home.detentConfiguration.initialDetent
    }

    func test_init_stackedLayerStartsEmpty() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        expect(coordinator.stackedRoutes).to(beEmpty())
        expect(coordinator.stackedDetents).to(beEmpty())
    }

    // MARK: - Push dispatches by prefersStacking

    func test_push_nonStackingRoute_appendsContentStackAndResetsDetent() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.search)

        expect(coordinator.routeStack.count) == 2
        expect(coordinator.currentRoute) == .search
        expect(coordinator.stackedRoutes).to(beEmpty())
        expect(coordinator.canPop) == true
        expect(coordinator.currentDetent) == AppSheetRoute.search.detentConfiguration.initialDetent
    }

    func test_push_stackingRoute_appendsToStackedAndLeavesContentStackAlone() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.search)

        coordinator.push(.tripPlanner)

        expect(coordinator.routeStack.count) == 2
        expect(coordinator.currentRoute) == .search
        expect(coordinator.stackedRoutes) == [.tripPlanner]
        expect(coordinator.stackedDetents) == [AppSheetRoute.tripPlanner.detentConfiguration.initialDetent]
    }

    func test_push_stackingRoute_stacksMultipleSheets() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.recentStopsAll)
        coordinator.push(.stopDetails(stopID: "1_75403"))
        coordinator.push(.tripDetails(tripID: "t1"))

        expect(coordinator.stackedRoutes) == [
            .recentStopsAll,
            .stopDetails(stopID: "1_75403"),
            .tripDetails(tripID: "t1")
        ]
        expect(coordinator.stackedDetents.count) == 3
    }

    // MARK: - Pop removes topmost layer

    func test_pop_withStackedPresented_removesTopStackedAndPreservesContentStack() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.search)
        coordinator.push(.tripPlanner)
        coordinator.push(.stopDetails(stopID: "1"))

        coordinator.pop()

        expect(coordinator.stackedRoutes) == [.tripPlanner]
        expect(coordinator.stackedDetents.count) == 1
        expect(coordinator.routeStack.count) == 2
        expect(coordinator.currentRoute) == .search
    }

    func test_pop_lastStackedRoute_emptiesStackedLayer() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.tripPlanner)

        coordinator.pop()

        expect(coordinator.stackedRoutes).to(beEmpty())
        expect(coordinator.stackedDetents).to(beEmpty())
    }

    func test_pop_withoutStacked_removesTopAndRestoresPreviousInitialDetent() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.search)
        coordinator.currentDetent = .medium

        coordinator.pop()

        expect(coordinator.routeStack.count) == 1
        expect(coordinator.currentRoute) == .home
        expect(coordinator.canPop) == false
        expect(coordinator.currentDetent) == AppSheetRoute.home.detentConfiguration.initialDetent
    }

    func test_pop_atRoot_isNoOp() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.currentDetent = .large

        coordinator.pop()

        expect(coordinator.routeStack.count) == 1
        expect(coordinator.currentRoute) == .home
        expect(coordinator.currentDetent) == .large
    }

    // MARK: - truncateStacked (OS-driven dismiss)

    func test_truncateStacked_removesEverythingAtAndAboveDepth() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.recentStopsAll)
        coordinator.push(.stopDetails(stopID: "1"))
        coordinator.push(.tripDetails(tripID: "t"))

        coordinator.truncateStacked(toDepth: 1)

        expect(coordinator.stackedRoutes) == [.recentStopsAll]
        expect(coordinator.stackedDetents.count) == 1
    }

    func test_truncateStacked_ignoresOutOfRangeDepth() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.tripPlanner)

        coordinator.truncateStacked(toDepth: 5)

        expect(coordinator.stackedRoutes) == [.tripPlanner]
    }

    // MARK: - setStackedDetent

    func test_setStackedDetent_persistsAtGivenDepth() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.tripPlanner)
        coordinator.push(.stopDetails(stopID: "1"))

        coordinator.setStackedDetent(.medium, at: 0)
        coordinator.setStackedDetent(.large, at: 1)

        expect(coordinator.stackedDetents) == [.medium, .large]
    }

    func test_setStackedDetent_ignoresOutOfRangeDepth() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.tripPlanner)
        let original = coordinator.stackedDetents

        coordinator.setStackedDetent(.medium, at: 5)

        expect(coordinator.stackedDetents) == original
    }

    // MARK: - stackedRoute(at:) / stackedDetent(at:fallback:)

    func test_stackedRoute_atDepth_returnsRouteWhenInRange() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.tripPlanner)
        coordinator.push(.stopDetails(stopID: "1"))

        expect(coordinator.stackedRoute(at: 0)) == .tripPlanner
        expect(coordinator.stackedRoute(at: 1)) == .stopDetails(stopID: "1")
    }

    func test_stackedRoute_atDepth_returnsNilWhenOutOfRange() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        expect(coordinator.stackedRoute(at: 0)).to(beNil())

        coordinator.push(.tripPlanner)
        expect(coordinator.stackedRoute(at: 1)).to(beNil())
    }

    func test_stackedDetent_atDepth_returnsStoredDetent() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.tripPlanner)
        coordinator.setStackedDetent(.medium, at: 0)

        expect(coordinator.stackedDetent(at: 0, fallback: .large)) == .medium
    }

    func test_stackedDetent_atDepth_returnsFallbackWhenOutOfRange() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        expect(coordinator.stackedDetent(at: 0, fallback: .large)) == .large
    }

    // MARK: - canPop / popToRoot / currentDetents

    func test_canPop_isTrueWhenOnlyStackedPresented() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        expect(coordinator.canPop) == false

        coordinator.push(.tripPlanner)
        expect(coordinator.canPop) == true
    }

    func test_popToRoot_clearsStackedAndUnwindsContentStack() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.search)
        coordinator.push(.nearbyAll)        // stacked
        coordinator.push(.recentStopsAll)   // also stacked

        coordinator.popToRoot()

        expect(coordinator.routeStack.count) == 1
        expect(coordinator.currentRoute) == .home
        expect(coordinator.stackedRoutes).to(beEmpty())
        expect(coordinator.stackedDetents).to(beEmpty())
        expect(coordinator.canPop) == false
        expect(coordinator.currentDetent) == AppSheetRoute.home.detentConfiguration.initialDetent
    }

    func test_currentDetents_reflectsContentStackTopRegardlessOfStacked() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        expect(coordinator.currentDetents) == AppSheetRoute.home.detentConfiguration.detents

        coordinator.push(.search)
        expect(coordinator.currentDetents) == AppSheetRoute.search.detentConfiguration.detents

        coordinator.push(.tripPlanner) // stacked — must not alter currentDetents
        expect(coordinator.currentDetents) == AppSheetRoute.search.detentConfiguration.detents
    }
}
