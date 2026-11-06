//
//  MapPanelBottomPaddingTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import SwiftUI
@testable import OBAKit

@MainActor
@Suite(.serialized)
struct MapPanelBottomPaddingTests {

    @Test func `Effective padding returns minimumPaddingFloor when total map height is zero`() {
        let padding = MapPanelBottomPadding.effectivePadding(
            sheetHeight: 350,
            totalMapHeight: 0
        )
        #expect(padding == MapPanelBottomPadding.minimumPaddingFloor)
    }

    @Test func `Effective padding enforces minimumPaddingFloor when sheet is at or below floor`() {
        let paddingAtCollapsed = MapPanelBottomPadding.effectivePadding(
            sheetHeight: AppSheetRoute.homeCollapsedHeight,
            totalMapHeight: 800
        )
        #expect(paddingAtCollapsed == MapPanelBottomPadding.minimumPaddingFloor)

        let paddingBelowFloor = MapPanelBottomPadding.effectivePadding(
            sheetHeight: 30,
            totalMapHeight: 800
        )
        #expect(paddingBelowFloor == MapPanelBottomPadding.minimumPaddingFloor)
    }

    @Test func `Effective padding tracks medium detent sheet height exactly above floor`() {
        let mediumHeight: CGFloat = 380
        let totalMapHeight: CGFloat = 850

        let padding = MapPanelBottomPadding.effectivePadding(
            sheetHeight: mediumHeight,
            totalMapHeight: totalMapHeight
        )
        #expect(padding == mediumHeight)
    }

    @Test func `Effective padding clamps to preserve minimum visible map height when sheet is at large detent`() {
        let totalMapHeight: CGFloat = 800
        let largeSheetHeight: CGFloat = 780

        let padding = MapPanelBottomPadding.effectivePadding(
            sheetHeight: largeSheetHeight,
            totalMapHeight: totalMapHeight
        )

        let expectedMaxAllowed = totalMapHeight - MapPanelBottomPadding.minimumVisibleMapHeight
        #expect(padding == expectedMaxAllowed)
        #expect(padding == 680)
    }

    @Test func `Tallest visible sheet height selects base sheet height when top stacked sheet is dragged to tip detent`() {
        let baseRoute = AppSheetRoute.home
        let topStackedRoute = AppSheetRoute.tripPlanner(TripPlannerRequest(origin: nil, destination: nil))

        let visibleRoutes: [AppSheetRoute] = [baseRoute, topStackedRoute]
        let measuredHeights: [AppSheetRoute: CGFloat] = [
            baseRoute: 390,
            topStackedRoute: 80
        ]

        let height = MapPanelBottomPadding.tallestVisibleSheetHeight(
            visibleRoutes: visibleRoutes,
            measuredHeights: measuredHeights,
            estimatedHeightForRoute: { _ in 0 }
        )

        // Must pick the 390pt base sheet height so map annotations don't slip under the base sheet
        #expect(height == 390)
    }

    @Test func `Tallest visible sheet height selects stacked sheet height when stacked sheet is taller than base`() {
        let baseRoute = AppSheetRoute.home
        let topStackedRoute = AppSheetRoute.stopDetails(stopID: "1_10020")

        let visibleRoutes: [AppSheetRoute] = [baseRoute, topStackedRoute]
        let measuredHeights: [AppSheetRoute: CGFloat] = [
            baseRoute: 75,
            topStackedRoute: 420
        ]

        let height = MapPanelBottomPadding.tallestVisibleSheetHeight(
            visibleRoutes: visibleRoutes,
            measuredHeights: measuredHeights,
            estimatedHeightForRoute: { _ in 0 }
        )

        #expect(height == 420)
    }

    @Test func `Tallest visible sheet height falls back to estimated height for unmeasured newly pushed route`() {
        let baseRoute = AppSheetRoute.home
        let newlyPushedRoute = AppSheetRoute.routePicker

        let visibleRoutes: [AppSheetRoute] = [baseRoute, newlyPushedRoute]
        let measuredHeights: [AppSheetRoute: CGFloat] = [
            baseRoute: 75
        ]

        let height = MapPanelBottomPadding.tallestVisibleSheetHeight(
            visibleRoutes: visibleRoutes,
            measuredHeights: measuredHeights,
            estimatedHeightForRoute: { route in
                route == newlyPushedRoute ? 360 : 75
            }
        )

        #expect(height == 360)
    }

    @Test func `Tallest visible sheet height retains base sheet measured height after stacked sheet dismissal`() {
        let baseRoute = AppSheetRoute.home
        // Stacked sheet was dismissed, only baseRoute is visible
        let visibleRoutes: [AppSheetRoute] = [baseRoute]
        let measuredHeights: [AppSheetRoute: CGFloat] = [
            baseRoute: 390
        ]

        let height = MapPanelBottomPadding.tallestVisibleSheetHeight(
            visibleRoutes: visibleRoutes,
            measuredHeights: measuredHeights,
            estimatedHeightForRoute: { _ in 75 }
        )

        #expect(height == 390)
    }

    @Test func `Tallest visible sheet height returns minimumPaddingFloor when visible routes is empty`() {
        let height = MapPanelBottomPadding.tallestVisibleSheetHeight(
            visibleRoutes: [AppSheetRoute](),
            measuredHeights: [:],
            estimatedHeightForRoute: { _ in 0 }
        )
        #expect(height == MapPanelBottomPadding.minimumPaddingFloor)
    }

    @Test func `Estimated height resolves homeCollapsedHeight detent`() {
        let height = MapPanelBottomPadding.estimatedHeight(
            for: .height(AppSheetRoute.homeCollapsedHeight),
            halfScreenHeight: 400,
            totalMapHeight: 800
        )
        #expect(height == AppSheetRoute.homeCollapsedHeight)
    }

    @Test func `Estimated height resolves tripPlannerTipHeight detent`() {
        let height = MapPanelBottomPadding.estimatedHeight(
            for: .height(AppSheetRoute.tripPlannerTipHeight),
            halfScreenHeight: 400,
            totalMapHeight: 800
        )
        #expect(height == AppSheetRoute.tripPlannerTipHeight)
    }

    @Test func `Estimated height resolves medium detent to half screen height`() {
        let halfHeight: CGFloat = 412
        let height = MapPanelBottomPadding.estimatedHeight(
            for: .medium,
            halfScreenHeight: halfHeight,
            totalMapHeight: 824
        )
        #expect(height == halfHeight)
    }

    @Test func `Estimated height resolves large and largeDetent to 0.99 fraction of map height`() {
        let totalHeight: CGFloat = 800
        let heightFromLarge = MapPanelBottomPadding.estimatedHeight(
            for: .large,
            halfScreenHeight: 400,
            totalMapHeight: totalHeight
        )
        #expect(heightFromLarge == totalHeight * 0.99)

        let heightFromLargeDetent = MapPanelBottomPadding.estimatedHeight(
            for: AppSheetRoute.largeDetent,
            halfScreenHeight: 400,
            totalMapHeight: totalHeight
        )
        #expect(heightFromLargeDetent == totalHeight * 0.99)
    }
}
