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

    @Test func `Effective padding returns collapsed height when total map height is zero`() {
        let padding = MapPanelBottomPadding.effectivePadding(
            sheetHeight: 350,
            totalMapHeight: 0
        )
        #expect(padding == AppSheetRoute.homeCollapsedHeight)
    }

    @Test func `Effective padding returns collapsed height when sheet is at or below collapsed height`() {
        let paddingAtCollapsed = MapPanelBottomPadding.effectivePadding(
            sheetHeight: AppSheetRoute.homeCollapsedHeight,
            totalMapHeight: 800
        )
        #expect(paddingAtCollapsed == AppSheetRoute.homeCollapsedHeight)

        let paddingBelowCollapsed = MapPanelBottomPadding.effectivePadding(
            sheetHeight: 30,
            totalMapHeight: 800
        )
        #expect(paddingBelowCollapsed == AppSheetRoute.homeCollapsedHeight)
    }

    @Test func `Effective padding tracks medium detent sheet height exactly`() {
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
