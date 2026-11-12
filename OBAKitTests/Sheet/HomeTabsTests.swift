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

    private static let collapsed = AppSheetRoute.homeCollapsedDetent

    // MARK: - Tabs

    @Test func `The tabs run Home, Recent, Bookmarks, More`() {
        #expect(HomeTab.allCases == [.home, .recent, .bookmarks, .more])
    }

    /// The classic tab bar's titles, so the panel's tabs arrive translated.
    @Test func `Recent, Bookmarks and More reuse the classic tabs' titles`() {
        #expect(HomeTab.recent.title == OBAKit.OBALoc("recent_stops_controller.title", value: "Recent", comment: ""))
        #expect(HomeTab.bookmarks.title == OBAKit.OBALoc("bookmarks_controller.title", value: "Bookmarks", comment: ""))
        #expect(HomeTab.more.title == OBAKit.OBALoc("more_controller.title", value: "More", comment: ""))
        #expect(HomeTab.home.title == OBAKit.OBALoc("home_sheet.tab.home", value: "Home", comment: ""))
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
        #expect(HomeTabs.detent(afterSelectingFrom: Self.collapsed) == .medium)
    }

    @Test func `Picking a tab on a raised sheet leaves it where it is`() {
        #expect(HomeTabs.detent(afterSelectingFrom: .medium) == nil)
        #expect(HomeTabs.detent(afterSelectingFrom: AppSheetRoute.largeDetent) == nil)
    }

    /// Collapsed, the sheet holds the search field and the tab bar under it, and no
    /// more, so it reads as those two controls rather than a list cut off.
    @Test func `The collapsed sheet is the search row plus the tab bar`() {
        #expect(AppSheetRoute.homeCollapsedHeight == AppSheetRoute.homeSearchRowHeight + AppSheetRoute.homeTabBarHeight)
    }

    /// Collapsed, Home is the search field over the bar. A list peeking through
    /// the sliver between them reads as cut off.
    @Test func `Home hides its list with less than a row of room under the search field`() {
        let search = AppSheetRoute.homeSearchRowHeight
        #expect(!HomeTabs.showsHomeList(showsTabs: true, pageHeight: search + 30))
        #expect(HomeTabs.showsHomeList(showsTabs: true, pageHeight: search + HomeTabs.minimumListRoom))
        #expect(HomeTabs.showsHomeList(showsTabs: true, pageHeight: 400))
    }

    /// Without tabs there's no bar for it to peek against, as before.
    @Test func `Without tabs the list shows at any height`() {
        #expect(HomeTabs.showsHomeList(showsTabs: false, pageHeight: 0))
    }

    /// A floating sheet stops short of the screen's edge and the home indicator
    /// may cross it, as in Find My, so the bar needs no room under it there; a
    /// sheet reaching the screen's edge does.
    @Test func `The bar clears the home indicator only on a sheet reaching the screen's edge`() {
        let screen = ScreenBottom(safeArea: 840, edge: 874)
        // Floating: 11 pt short of the edge, overlapping the indicator.
        #expect(HomeTabs.bottomClearance(sheetBottom: 863, screen: screen) == 0)
        #expect(HomeTabs.bottomClearance(sheetBottom: 874, screen: screen) == 34)
        // Not yet measured.
        #expect(HomeTabs.bottomClearance(sheetBottom: 874, screen: ScreenBottom()) == 0)
    }

    /// A floating sheet runs past its detent into the home indicator's area; the
    /// collapsed detent gives that back, so search and the bar fill it exactly.
    @Test func `A floating sheet reports how far it runs past the safe area`() {
        let screen = ScreenBottom(safeArea: 840, edge: 874)
        #expect(HomeTabs.floatingOverlap(sheetBottom: 863, screen: screen) == 23)
        // Ends above the safe area (a home-button phone, or a raised keyboard).
        #expect(HomeTabs.floatingOverlap(sheetBottom: 820, screen: screen) == 0)
        // Not floating, or not measured: nothing to learn.
        #expect(HomeTabs.floatingOverlap(sheetBottom: 874, screen: screen) == nil)
        #expect(HomeTabs.floatingOverlap(sheetBottom: 863, screen: ScreenBottom()) == nil)
    }

    @Test func `The collapsed detent gives back the floating overlap`() {
        #expect(HomeCollapsedDetent.height(floatingOverlap: 0) == AppSheetRoute.homeCollapsedHeight)
        #expect(HomeCollapsedDetent.height(floatingOverlap: 23) == AppSheetRoute.homeCollapsedHeight - 23)
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
