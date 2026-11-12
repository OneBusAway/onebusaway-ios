//
//  HomeTabsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// The home sheet's tabs on iPhone: Home, Recent, Bookmarks and More, in a bar
/// pinned to the bottom of the sheet, as Find My lays its sheet out.
@MainActor
@Suite(.serialized)
struct HomeTabsTests {

    private static let collapsed = PresentationDetent.height(AppSheetRoute.homeCollapsedHeight)

    // MARK: - Tabs

    @Test func `The tabs run Home, Recent, Bookmarks, More`() {
        #expect(HomeTab.allCases == [.home, .recent, .bookmarks, .more])
    }

    /// The classic tab bar's titles, so the panel's tabs arrive translated.
    @Test func `Recent, Bookmarks and More reuse the classic tabs' titles`() {
        #expect(HomeTab.recent.title == OBAKit.OBALoc("recent_stops_controller.title", value: "Recent", comment: ""))
        #expect(HomeTab.bookmarks.title == OBAKit.OBALoc("bookmarks_controller.title", value: "Bookmarks", comment: ""))
        #expect(HomeTab.more.title == OBAKit.OBALoc("more_controller.title", value: "More", comment: ""))
        #expect(HomeTab.home.title == "Home")
    }

    @Test func `Every tab has a distinct symbol`() {
        let symbols = HomeTab.allCases.map(\.systemImage)
        #expect(Set(symbols).count == symbols.count)
        #expect(symbols.allSatisfy { UIImage(systemName: $0) != nil })
    }

    // MARK: - Where they show

    @Test func `Tabs show in compact width only`() {
        #expect(HomeTabs.showsTabs(horizontalSizeClass: .compact))
        #expect(!HomeTabs.showsTabs(horizontalSizeClass: .regular))
        // Unknown on the first pass; iPhone is what this release targets.
        #expect(HomeTabs.showsTabs(horizontalSizeClass: nil))
    }

    // MARK: - The sheet

    /// Find My: picking a tab on a collapsed sheet raises it so the tab can be seen.
    @Test func `Picking a tab on the collapsed sheet raises it to medium`() {
        for tab in HomeTab.allCases {
            #expect(HomeTabs.detent(afterSelecting: tab, currentDetent: Self.collapsed) == .medium)
        }
    }

    @Test func `Picking a tab on a raised sheet leaves it where it is`() {
        #expect(HomeTabs.detent(afterSelecting: .recent, currentDetent: .medium) == nil)
        #expect(HomeTabs.detent(afterSelecting: .more, currentDetent: AppSheetRoute.largeDetent) == nil)
    }

    /// Collapsed, the sheet holds the search field and the tab bar under it, and no
    /// more, so it reads as those two controls rather than a list cut off.
    @Test func `The collapsed sheet is the search row plus the tab bar`() {
        #expect(AppSheetRoute.homeCollapsedHeight == AppSheetRoute.homeSearchRowHeight + HomeTabBar.height)
    }

    /// Collapsed, Home is the search field over the bar. A list peeking between
    /// them reads as cut off.
    @Test func `The collapsed sheet hides Home's list behind the tabs`() {
        #expect(!HomeTabs.showsHomeList(showsTabs: true, currentDetent: Self.collapsed))
        #expect(HomeTabs.showsHomeList(showsTabs: true, currentDetent: .medium))
    }

    /// Without tabs there's no bar for it to peek against, as before.
    @Test func `Without tabs the list shows at every detent`() {
        #expect(HomeTabs.showsHomeList(showsTabs: false, currentDetent: Self.collapsed))
    }

    // MARK: - See all

    /// With the tabs on screen, a section's header goes to its tab rather than
    /// stacking a second copy of it over the home sheet.
    @Test func `Recent and Bookmarks headers go to their tabs`() {
        #expect(HomeTab(seeAll: .recentStopsAll) == .recent)
        #expect(HomeTab(seeAll: .bookmarksAll) == .bookmarks)
    }

    /// Nearby has no tab: its header still opens the full list.
    @Test func `Nearby has no tab`() {
        #expect(HomeTab(seeAll: .nearbyAll) == nil)
        #expect(HomeTab(seeAll: .home) == nil)
    }
}
