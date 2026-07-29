//
//  SheetCoordinatorTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
@testable import OBAKit

/// Behavior tests for `SheetCoordinator`'s content-swap and stacked navigation,
/// using `AppSheetRoute` as the concrete `SheetRouteable` driver.
@MainActor
@Suite(.serialized)
final class SheetCoordinatorTests {

    // MARK: - Init

    @Test func `Init seeds route stack with root`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        #expect(coordinator.routeStack.count == 1)
        #expect(coordinator.currentRoute == .home)
        #expect(coordinator.canPop == false)
    }

    @Test func `Init sets current detent to root initial detent`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        #expect(coordinator.currentDetent == AppSheetRoute.home.detentConfiguration.initialDetent)
    }

    @Test func `Init stacked layer starts empty`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        #expect(coordinator.stackedRoutes.isEmpty)
        #expect(coordinator.stackedDetents.isEmpty)
    }

    // MARK: - Push dispatches by prefersStacking

    @Test func `Push non stacking route appends content stack and resets detent`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.search)

        #expect(coordinator.routeStack.count == 2)
        #expect(coordinator.currentRoute == .search)
        #expect(coordinator.stackedRoutes.isEmpty)
        #expect(coordinator.canPop == true)
        #expect(coordinator.currentDetent == AppSheetRoute.search.detentConfiguration.initialDetent)
    }

    @Test func `Push stacking route appends to stacked and leaves content stack alone`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.search)

        coordinator.push(.tripPlanner)

        #expect(coordinator.routeStack.count == 2)
        #expect(coordinator.currentRoute == .search)
        #expect(coordinator.stackedRoutes == [.tripPlanner])
        #expect(coordinator.stackedDetents == [AppSheetRoute.tripPlanner.detentConfiguration.initialDetent])
    }

    @Test func `Push stacking route stacks multiple sheets`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.recentStopsAll)
        coordinator.push(.stopDetails(stopID: "1_75403"))
        coordinator.push(.tripDetails(tripID: "t1"))

        #expect(coordinator.stackedRoutes == [
            .recentStopsAll,
            .stopDetails(stopID: "1_75403"),
            .tripDetails(tripID: "t1")
        ])
        #expect(coordinator.stackedDetents.count == 3)
    }

    // MARK: - Pop removes topmost layer

    @Test func `Pop with stacked presented removes top stacked and preserves content stack`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.search)
        coordinator.push(.tripPlanner)
        coordinator.push(.stopDetails(stopID: "1"))

        coordinator.pop()

        #expect(coordinator.stackedRoutes == [.tripPlanner])
        #expect(coordinator.stackedDetents.count == 1)
        #expect(coordinator.routeStack.count == 2)
        #expect(coordinator.currentRoute == .search)
    }

    @Test func `Pop last stacked route empties stacked layer`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.tripPlanner)

        coordinator.pop()

        #expect(coordinator.stackedRoutes.isEmpty)
        #expect(coordinator.stackedDetents.isEmpty)
    }

    @Test func `Pop without stacked removes top and restores previous initial detent`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.search)
        coordinator.currentDetent = .medium

        coordinator.pop()

        #expect(coordinator.routeStack.count == 1)
        #expect(coordinator.currentRoute == .home)
        #expect(coordinator.canPop == false)
        #expect(coordinator.currentDetent == AppSheetRoute.home.detentConfiguration.initialDetent)
    }

    @Test func `Pop at root is no op`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.currentDetent = .large

        coordinator.pop()

        #expect(coordinator.routeStack.count == 1)
        #expect(coordinator.currentRoute == .home)
        #expect(coordinator.currentDetent == .large)
    }

    // MARK: - truncateStacked (OS-driven dismiss)

    @Test func `Truncate stacked removes everything at and above depth`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.recentStopsAll)
        coordinator.push(.stopDetails(stopID: "1"))
        coordinator.push(.tripDetails(tripID: "t"))

        coordinator.truncateStacked(toDepth: 1)

        #expect(coordinator.stackedRoutes == [.recentStopsAll])
        #expect(coordinator.stackedDetents.count == 1)
    }

    @Test func `Truncate stacked ignores out of range depth`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.tripPlanner)

        coordinator.truncateStacked(toDepth: 5)

        #expect(coordinator.stackedRoutes == [.tripPlanner])
    }

    // MARK: - setStackedDetent

    @Test func `Set stacked detent persists at given depth`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.tripPlanner)
        coordinator.push(.stopDetails(stopID: "1"))

        coordinator.setStackedDetent(.medium, at: 0)
        coordinator.setStackedDetent(.large, at: 1)

        #expect(coordinator.stackedDetents == [.medium, .large])
    }

    @Test func `Set stacked detent ignores out of range depth`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.tripPlanner)
        let original = coordinator.stackedDetents

        coordinator.setStackedDetent(.medium, at: 5)

        #expect(coordinator.stackedDetents == original)
    }

    // MARK: - stackedRoute(at:) / stackedDetent(at:fallback:)

    @Test func `Stacked route at depth returns route when in range`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.tripPlanner)
        coordinator.push(.stopDetails(stopID: "1"))

        #expect(coordinator.stackedRoute(at: 0) == .tripPlanner)
        #expect(coordinator.stackedRoute(at: 1) == .stopDetails(stopID: "1"))
    }

    @Test func `Stacked route at depth returns nil when out of range`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        #expect(coordinator.stackedRoute(at: 0) == nil)

        coordinator.push(.tripPlanner)
        #expect(coordinator.stackedRoute(at: 1) == nil)
    }

    @Test func `Stacked detent at depth returns stored detent`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.tripPlanner)
        coordinator.setStackedDetent(.medium, at: 0)

        #expect(coordinator.stackedDetent(at: 0, fallback: .large) == .medium)
    }

    @Test func `Stacked detent at depth returns fallback when out of range`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        #expect(coordinator.stackedDetent(at: 0, fallback: .large) == .large)
    }

    // MARK: - canPop / popToRoot / currentDetents

    @Test func `Can pop is true when only stacked presented`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        #expect(coordinator.canPop == false)

        coordinator.push(.tripPlanner)
        #expect(coordinator.canPop == true)
    }

    @Test func `Pop to root clears stacked and unwinds content stack`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.search)
        coordinator.push(.nearbyAll)        // stacked
        coordinator.push(.recentStopsAll)   // also stacked

        coordinator.popToRoot()

        #expect(coordinator.routeStack.count == 1)
        #expect(coordinator.currentRoute == .home)
        #expect(coordinator.stackedRoutes.isEmpty)
        #expect(coordinator.stackedDetents.isEmpty)
        #expect(coordinator.canPop == false)
        #expect(coordinator.currentDetent == AppSheetRoute.home.detentConfiguration.initialDetent)
    }

    @Test func `Current detents reflects content stack top regardless of stacked`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        #expect(coordinator.currentDetents == AppSheetRoute.home.detentConfiguration.detents)

        coordinator.push(.search)
        #expect(coordinator.currentDetents == AppSheetRoute.search.detentConfiguration.detents)

        coordinator.push(.tripPlanner) // stacked — must not alter currentDetents
        #expect(coordinator.currentDetents == AppSheetRoute.search.detentConfiguration.detents)
    }
}
