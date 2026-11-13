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
        let search: CGFloat = 80
        #expect(!HomeTabs.showsHomeList(showsTabs: true, pageHeight: search + 30, searchRowHeight: search))
        #expect(HomeTabs.showsHomeList(showsTabs: true, pageHeight: search + HomeTabs.minimumListRoom, searchRowHeight: search))
        #expect(HomeTabs.showsHomeList(showsTabs: true, pageHeight: 400, searchRowHeight: search))
    }

    /// Without tabs there's no bar for it to peek against, as before.
    @Test func `Without tabs the list shows at any height`() {
        #expect(HomeTabs.showsHomeList(showsTabs: false, pageHeight: 0, searchRowHeight: 80))
    }

    /// A floating sheet stops short of the screen's edge and the home indicator
    /// may cross it, as in Find My, so the bar needs no room under it there; a
    /// sheet reaching the screen's edge does.
    @Test func `The bar clears the home indicator only on a sheet reaching the screen's edge`() {
        let screen = ScreenBottom(edge: 874, inset: 34)
        // Floating: 11 pt short of the edge, overlapping the indicator.
        #expect(HomeTabs.bottomClearance(sheetBottom: 863, screen: screen) == 0)
        #expect(HomeTabs.bottomClearance(sheetBottom: 874, screen: screen) == 34)
        // Not yet measured.
        #expect(HomeTabs.bottomClearance(sheetBottom: 874, screen: ScreenBottom()) == 0)
    }

    /// The system draws the sheet taller than its detent: a floating sheet runs
    /// into the home indicator's area, and a little more. Learned from the sheet
    /// as drawn, so the collapsed sheet is the search row and the bar, exactly.
    @Test func `The collapsed detent learns how much taller the sheet is drawn`() {
        #expect(HomeCollapsedDetent.sheetExtra(sheetHeight: 166.5, requested: 136) == 30.5)
    }

    /// Mid-drag, the sheet is taller than the detent because of the finger, not
    /// the system; that isn't learned.
    @Test func `A long drag doesn't teach the collapsed detent`() {
        #expect(HomeCollapsedDetent.sheetExtra(sheetHeight: 400, requested: 136) == nil)
        #expect(HomeCollapsedDetent.sheetExtra(sheetHeight: 100, requested: 136) == nil)
    }

    /// Learned once: later measurements at the collapsed detent may be a slow
    /// drag's, which would walk the value along with the finger.
    @Test func `The collapsed detent learns its extra once per screen`() {
        let saved = HomeCollapsedDetent.measured.withLock { $0 }
        defer { HomeCollapsedDetent.measured.withLock { $0 = saved } }
        HomeCollapsedDetent.measured.withLock { $0 = .init(requested: 100) }

        HomeCollapsedDetent.learn(sheetHeight: 130)
        HomeCollapsedDetent.learn(sheetHeight: 132)
        #expect(HomeCollapsedDetent.measured.withLock { $0.sheetExtra } == 30)

        HomeCollapsedDetent.forgetSheetExtra()
        HomeCollapsedDetent.learn(sheetHeight: 121)
        #expect(HomeCollapsedDetent.measured.withLock { $0.sheetExtra } == 21)
    }

    @Test func `The collapsed detent gives back what the sheet is drawn taller`() {
        #expect(HomeCollapsedDetent.height(.init()) == AppSheetRoute.homeCollapsedHeight)
        #expect(HomeCollapsedDetent.height(.init(sheetExtra: 29.5)) == AppSheetRoute.homeCollapsedHeight - 29.5)
    }

    /// Fitted to the search row as laid out, so the gap over the bar is the row's
    /// own bottom padding at any text size, not that plus a fixed estimate's slack.
    @Test func `The collapsed detent fits the measured search row`() {
        #expect(HomeCollapsedDetent.height(.init(searchRowHeight: 90)) == 90 + AppSheetRoute.homeTabBarHeight)
        #expect(HomeCollapsedDetent.height(.init(searchRowHeight: 90, sheetExtra: 26)) == 90 + AppSheetRoute.homeTabBarHeight - 26)
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
