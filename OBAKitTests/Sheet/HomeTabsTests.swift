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

/// The home sheet's tabs on iPhone: Home, Recent, Bookmarks and More, in a bar
/// pinned to the bottom of the sheet, as Find My lays its sheet out.
@MainActor
@Suite(.serialized)
struct HomeTabsTests {

    private static let collapsed = AppSheetRoute.homeCollapsedDetent

    // MARK: - Tabs

    /// The filters under the search field, in the order they read: the mixed
    /// view first, then one per section of it.
    @Test func `The tabs run For You, Bookmarks, Nearby, Recent`() {
        #expect(HomeTab.allCases == [.home, .bookmarks, .nearby, .recent])
    }

    /// The classic tab bar's titles, so the panel's tabs arrive translated.
    @Test func `Recent and Bookmarks reuse the classic tabs' titles`() {
        #expect(HomeTab.recent.title == OBAKit.OBALoc("recent_stops_controller.title", value: "Recent", comment: ""))
        #expect(HomeTab.bookmarks.title == OBAKit.OBALoc("bookmarks_controller.title", value: "Bookmarks", comment: ""))
    }

    @Test func `For You and Nearby have titles of their own`() {
        #expect(HomeTab.home.title == OBAKit.OBALoc("home_sheet.tab.for_you", value: "For You", comment: ""))
        #expect(HomeTab.nearby.title == OBAKit.OBALoc("home_sheet.tab.nearby", value: "Nearby", comment: ""))
    }

    // MARK: - Nearby

    /// The Nearby tab keeps its list, scroll position and search text between
    /// visits, unless the map has moved to where other stops are near.
    @Test func `Nearby recenters only once the map has moved away`() {
        let here = CLLocationCoordinate2D(latitude: 47.6097, longitude: -122.3331)
        // About 50 m and 550 m north.
        let aStepAway = CLLocationCoordinate2D(latitude: 47.60975 + 0.0004, longitude: -122.3331)
        let blocksAway = CLLocationCoordinate2D(latitude: 47.6147, longitude: -122.3331)

        #expect(HomeTabs.nearbyAnchor(current: nil, mapCenter: here)?.latitude == here.latitude)
        #expect(HomeTabs.nearbyAnchor(current: here, mapCenter: aStepAway)?.latitude == here.latitude)
        #expect(HomeTabs.nearbyAnchor(current: here, mapCenter: blocksAway)?.latitude == blocksAway.latitude)
        // The map's center lost, as before its first settle: stay put.
        #expect(HomeTabs.nearbyAnchor(current: here, mapCenter: nil)?.latitude == here.latitude)
        #expect(HomeTabs.nearbyAnchor(current: nil, mapCenter: nil) == nil)
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
    @Test func `Bookmarks, Nearby and Recent headers go to their tabs`() {
        #expect(HomeTab(seeAll: .recentStopsAll) == .recent)
        #expect(HomeTab(seeAll: .bookmarksAll) == .bookmarks)
        #expect(HomeTab(seeAll: .nearbyAll) == .nearby)
    }

    @Test func `Other routes have no tab`() {
        #expect(HomeTab(seeAll: .home) == nil)
        #expect(HomeTab(seeAll: .more) == nil)
    }

    // MARK: - Collapsed header

    /// The detent is fitted to the field and its standard padding, never to
    /// the centering padding, which is itself derived from the detent.
    @Test func `The header measured for the detent is the field with its standard padding`() {
        #expect(HomeTabs.headerHeight(fieldHeight: 50) == 70)
    }

    /// Collapsed, the field sits in the middle of the sheet rather than over a
    /// band of nothing.
    @Test func `Collapsed, the search field is centered in the sheet`() {
        let collapsed = AppSheetRoute.homeCollapsedHeight
        #expect(HomeTabs.searchRowTopPadding(fieldHeight: 50, sheetHeight: collapsed) == (collapsed - 50) / 2)
        // A few points short, as the home view's frame can be.
        #expect(HomeTabs.searchRowTopPadding(fieldHeight: 50, sheetHeight: collapsed - 4) == (collapsed - 50) / 2)
    }

    /// Point for point, so the field follows a drag up, down to the standard.
    @Test func `As the sheet rises the field moves up to the standard padding`() {
        let collapsed = AppSheetRoute.homeCollapsedHeight
        let centered = (collapsed - 50) / 2
        #expect(HomeTabs.searchRowTopPadding(fieldHeight: 50, sheetHeight: collapsed + 10) == centered - 10)
        #expect(HomeTabs.searchRowTopPadding(fieldHeight: 50, sheetHeight: 400) == HomeTabs.searchRowStandardTopPadding)
    }

    /// At the largest text sizes the field outgrows the floor, and there's no
    /// extra to center it in.
    @Test func `A field taller than the floor keeps the standard padding`() {
        #expect(HomeTabs.searchRowTopPadding(fieldHeight: 140, sheetHeight: 160) == HomeTabs.searchRowStandardTopPadding)
    }

    @Test func `The chips show only with room for all of them`() {
        #expect(HomeTabs.showsChips(room: 52, chipsHeight: 52))
        #expect(!HomeTabs.showsChips(room: 30, chipsHeight: 52))
        #expect(!HomeTabs.showsChips(room: 0, chipsHeight: 0))
    }
}
