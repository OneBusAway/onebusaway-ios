//
//  MapPanelBottomPaddingTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Observation
import os
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

    @Test func `Tallest visible sheet height with detentForRoute retains base detent after stacked sheet dismissal`() {
        let baseRoute = AppSheetRoute.home
        // Stacked sheet was dismissed, only baseRoute is visible
        let visibleRoutes: [AppSheetRoute] = [baseRoute]

        let height = MapPanelBottomPadding.tallestVisibleSheetHeight(
            visibleRoutes: visibleRoutes,
            detentForRoute: { route in
                route == baseRoute ? .medium : AppSheetRoute.homeCollapsedDetent
            },
            halfScreenHeight: 350,
            totalMapHeight: 800,
            homeCollapsedHeight: AppSheetRoute.homeCollapsedHeight
        )

        #expect(height == 350)
    }

    @Test func `Tallest visible sheet height with detentForRoute selects base detent when stacked sheet is at tip detent`() {
        let baseRoute = AppSheetRoute.home
        let topStackedRoute = AppSheetRoute.tripPlanner(TripPlannerRequest(origin: nil, destination: nil))
        let visibleRoutes: [AppSheetRoute] = [baseRoute, topStackedRoute]

        let height = MapPanelBottomPadding.tallestVisibleSheetHeight(
            visibleRoutes: visibleRoutes,
            detentForRoute: { route in
                route == baseRoute ? .medium : .height(AppSheetRoute.tripPlannerTipHeight)
            },
            halfScreenHeight: 350,
            totalMapHeight: 800,
            homeCollapsedHeight: AppSheetRoute.homeCollapsedHeight
        )

        // Base sheet at .medium (350pt) must be selected over the 80pt tip detent
        #expect(height == 350)
    }

    @Test func `Tallest visible sheet height with detentForRoute selects stacked detent when stacked is larger`() {
        let baseRoute = AppSheetRoute.home
        let topStackedRoute = AppSheetRoute.stopDetails(stopID: "1_10020")
        let visibleRoutes: [AppSheetRoute] = [baseRoute, topStackedRoute]

        let height = MapPanelBottomPadding.tallestVisibleSheetHeight(
            visibleRoutes: visibleRoutes,
            detentForRoute: { route in
                route == baseRoute ? AppSheetRoute.homeCollapsedDetent : .medium
            },
            halfScreenHeight: 350,
            totalMapHeight: 800,
            homeCollapsedHeight: AppSheetRoute.homeCollapsedHeight
        )

        // Stacked sheet at .medium (350pt) must be selected over 75pt collapsed
        #expect(height == 350)
    }

    @Test func `Tallest visible sheet height with detentForRoute returns minimumPaddingFloor when routes empty`() {
        let height = MapPanelBottomPadding.tallestVisibleSheetHeight(
            visibleRoutes: [AppSheetRoute](),
            detentForRoute: { _ in .medium },
            halfScreenHeight: 350,
            totalMapHeight: 800,
            homeCollapsedHeight: AppSheetRoute.homeCollapsedHeight
        )
        #expect(height == MapPanelBottomPadding.minimumPaddingFloor)
    }

    /// The collapsed sheet as drawn, which follows the search row's measured
    /// height, so the map's padding matches it at any text size.
    @Test func `Estimated height resolves the collapsed home detent to the sheet as drawn`() {
        let height = MapPanelBottomPadding.estimatedHeight(
            for: AppSheetRoute.homeCollapsedDetent,
            halfScreenHeight: 400,
            totalMapHeight: 800,
            homeCollapsedHeight: 152
        )
        #expect(height == 152)
    }

    /// A larger text size makes the search row, and so the collapsed sheet, taller.
    /// The padding has to follow the new measurement, not wait for another redraw.
    @Test func `The padding follows a new collapsed height`() {
        func padding(collapsedHeight: CGFloat) -> CGFloat {
            let sheetHeight = MapPanelBottomPadding.tallestVisibleSheetHeight(
                visibleRoutes: [AppSheetRoute.home],
                detentForRoute: { _ in AppSheetRoute.homeCollapsedDetent },
                halfScreenHeight: 400,
                totalMapHeight: 800,
                homeCollapsedHeight: collapsedHeight
            )
            return MapPanelBottomPadding.effectivePadding(sheetHeight: sheetHeight, totalMapHeight: 800)
        }

        // Over the 180 pt floor, as at the largest text sizes.
        #expect(padding(collapsedHeight: 200) == 200)
        #expect(padding(collapsedHeight: 240) == 240)
    }

    /// `MapPanelRootView` reads the height from `HomeSheetMetrics`; a change to the
    /// measured search row has to redraw it.
    @Test func `A new search row height in the home sheet metrics redraws the map`() {
        let metrics = HomeSheetMetrics()
        let redraws = OSAllocatedUnfairLock(initialState: 0)
        withObservationTracking {
            _ = metrics.collapsedHeight
        } onChange: {
            redraws.withLock { $0 += 1 }
        }

        metrics.searchRowHeight = 120

        #expect(redraws.withLock { $0 } == 1)
        #expect(metrics.collapsedHeight == 120 + AppSheetRoute.homeTabBarHeight)
    }

    @Test func `Estimated height resolves tripPlannerTipHeight detent`() {
        let height = MapPanelBottomPadding.estimatedHeight(
            for: .height(AppSheetRoute.tripPlannerTipHeight),
            halfScreenHeight: 400,
            totalMapHeight: 800,
            homeCollapsedHeight: AppSheetRoute.homeCollapsedHeight
        )
        #expect(height == AppSheetRoute.tripPlannerTipHeight)
    }

    @Test func `Estimated height resolves medium detent to half screen height`() {
        let halfHeight: CGFloat = 412
        let height = MapPanelBottomPadding.estimatedHeight(
            for: .medium,
            halfScreenHeight: halfHeight,
            totalMapHeight: 824,
            homeCollapsedHeight: AppSheetRoute.homeCollapsedHeight
        )
        #expect(height == halfHeight)
    }

    @Test func `Estimated height resolves large and largeDetent to 0.99 fraction of map height`() {
        let totalHeight: CGFloat = 800
        let heightFromLarge = MapPanelBottomPadding.estimatedHeight(
            for: .large,
            halfScreenHeight: 400,
            totalMapHeight: totalHeight,
            homeCollapsedHeight: AppSheetRoute.homeCollapsedHeight
        )
        #expect(heightFromLarge == totalHeight * 0.99)

        let heightFromLargeDetent = MapPanelBottomPadding.estimatedHeight(
            for: AppSheetRoute.largeDetent,
            halfScreenHeight: 400,
            totalMapHeight: totalHeight,
            homeCollapsedHeight: AppSheetRoute.homeCollapsedHeight
        )
        #expect(heightFromLargeDetent == totalHeight * 0.99)
    }
}
