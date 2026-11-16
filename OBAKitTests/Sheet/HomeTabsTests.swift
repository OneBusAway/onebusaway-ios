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
import CoreLocation
@testable import OBAKit
@testable import OBAKitCore

/// The home sheet's tabs on iPhone: Home, Recent and Bookmarks, in a bar under
/// the search field that shows at every detent, collapsed included (#1750).
@MainActor
@Suite(.serialized)
struct HomeTabsTests {

    private static let collapsed = AppSheetRoute.homeCollapsedDetent

    // MARK: - Tabs

    /// Home, which holds what leaves nearby, then Recent and Bookmarks. No
    /// Nearby tab: its content is on Home.
    @Test func `The tabs run Home, Recent, Bookmarks`() {
        #expect(HomeTab.allCases == [.home, .recent, .bookmarks])
    }

    /// An icon above each label, so the tab doesn't rely on its text alone.
    @Test func `Each tab has an icon`() {
        #expect(HomeTab.home.systemImage == "house")
        #expect(HomeTab.recent.systemImage == "clock")
        #expect(HomeTab.bookmarks.systemImage == "bookmark")
    }

    /// The classic tab bar's titles, so the panel's tabs arrive translated.
    @Test func `Recent and Bookmarks reuse the classic tabs' titles`() {
        #expect(HomeTab.recent.title == OBAKit.OBALoc("recent_stops_controller.title", value: "Recent", comment: ""))
        #expect(HomeTab.bookmarks.title == OBAKit.OBALoc("bookmarks_controller.title", value: "Bookmarks", comment: ""))
    }

    @Test func `Home has a title of its own`() {
        #expect(HomeTab.home.title == OBAKit.OBALoc("home_sheet.tab.home", value: "Home", comment: ""))
        #expect(HomeTab.home.title == "Home")
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

    /// Collapsed, the sheet is the search field over the chips, whichever tab is
    /// picked, and every tab hides its page: one peeking through a sliver under
    /// the chips reads as cut off.
    @Test func `The pages hide with less than a row of room under the header`() {
        #expect(!HomeTabs.showsTabPages(showsTabs: true, pageHeight: 0))
        #expect(!HomeTabs.showsTabPages(showsTabs: true, pageHeight: 30))
        #expect(HomeTabs.showsTabPages(showsTabs: true, pageHeight: HomeTabs.minimumListRoom))
        #expect(HomeTabs.showsTabPages(showsTabs: true, pageHeight: 400))
    }

    /// Without tabs there are no chips for a page to peek against.
    @Test func `Without tabs the page shows at any height`() {
        #expect(HomeTabs.showsTabPages(showsTabs: false, pageHeight: 0))
    }

    // MARK: - Polling

    /// A page's 30-second poll runs only while the rider can see the page.
    @Test func `A page polls only while it can be seen`() {
        #expect(HomeTabs.shouldPoll(isOnScreen: true, isCovered: false, isCollapsed: false))
        // Collapsed: the page is hidden behind the search row's room.
        #expect(!HomeTabs.shouldPoll(isOnScreen: true, isCovered: false, isCollapsed: true))
        // A stacked sheet covers it.
        #expect(!HomeTabs.shouldPoll(isOnScreen: true, isCovered: true, isCollapsed: false))
        // Another tab, or the sheet gone.
        #expect(!HomeTabs.shouldPoll(isOnScreen: false, isCovered: false, isCollapsed: false))
    }

    /// A floating sheet stops short of the screen's edge and the home indicator
    /// may cross it, as in Find My, so the bar needs no room under it there; a
    /// sheet reaching the screen's edge does.
    @Test func `A page clears the home indicator only on a sheet reaching the screen's edge`() {
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

    /// Fitted to the header as laid out, search field and chips, so both can
    /// grow with the text size rather than be held to an estimate.
    @Test func `The collapsed detent fits the measured header`() {
        #expect(HomeCollapsedDetent.height(.init(headerHeight: 190)) == 190)
        #expect(HomeCollapsedDetent.height(.init(headerHeight: 190, sheetExtra: 26)) == 164)
    }

    /// A shorter header, as on regular width, which has no chips: the system
    /// draws a floating sheet much under this narrower and lifted off the bottom.
    @Test func `The collapsed detent is never shorter than its estimate`() {
        #expect(HomeCollapsedDetent.height(.init(headerHeight: 70)) == AppSheetRoute.homeCollapsedHeight)
        #expect(HomeCollapsedDetent.height(.init(headerHeight: 70, sheetExtra: 26)) == AppSheetRoute.homeCollapsedHeight - 26)
    }

    // MARK: - See all

    /// With the tabs on screen, a section's header goes to its tab rather than
    /// stacking a second copy of it over the home sheet.
    @Test func `Bookmarks and Recent headers go to their tabs`() {
        #expect(HomeTab(seeAll: .recentStopsAll) == .recent)
        #expect(HomeTab(seeAll: .bookmarksAll) == .bookmarks)
    }

    /// No Nearby tab, so the Nearby Stops header stacks the full list, the only
    /// way into it now that the section has no "All Nearby Stops" row (#1752).
    @Test func `The Nearby Stops header has no tab to go to`() {
        #expect(HomeTab(seeAll: .nearbyAll) == nil)
    }

    @Test func `Other routes have no tab`() {
        #expect(HomeTab(seeAll: .home) == nil)
        #expect(HomeTab(seeAll: .more) == nil)
    }

    // MARK: - Collapsed header

    /// The detent is fitted to the header as laid out at its standard padding:
    /// the search field, then the tab bar.
    @Test func `The header measured for the detent is the field and the tab bar`() {
        #expect(HomeTabs.headerHeight(fieldHeight: 50, tabBarHeight: 60) == 130) // 16 + 50 + 4 + 60
    }

    /// Regular width has no tab bar.
    @Test func `Without a tab bar the header is the field with its padding`() {
        #expect(HomeTabs.headerHeight(fieldHeight: 50, tabBarHeight: 0) == 70)
    }

    /// Room for a row under the tabs, empty for now: the collapsed sheet grows
    /// by exactly that row.
    @Test func `A row under the tabs adds its own height`() {
        let without = HomeTabs.headerHeight(fieldHeight: 50, tabBarHeight: 60)
        #expect(HomeTabs.headerHeight(fieldHeight: 50, tabBarHeight: 60, accessoryHeight: 44) == without + 44)
    }

    /// The header grows with Dynamic Type, and the collapsed sheet with it.
    @Test func `The collapsed sheet follows a header taller than the floor`() {
        let header = HomeTabs.headerHeight(fieldHeight: 90, tabBarHeight: 120)
        #expect(HomeCollapsedDetent.collapsedHeight(headerHeight: header) == header)
    }
}
