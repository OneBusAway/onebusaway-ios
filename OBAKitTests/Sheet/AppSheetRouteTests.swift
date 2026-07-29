//
//  AppSheetRouteTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Pure-enum tests for `AppSheetRoute`: stable identifiers,
/// stacking preference, and per-detent configuration.
@MainActor
@Suite(.serialized)
final class AppSheetRouteTests {

    // MARK: - Identifiers

    @Test func `Id is stable for caseless routes`() {
        #expect(AppSheetRoute.home.id == "home")
        #expect(AppSheetRoute.search.id == "search")
        #expect(AppSheetRoute.nearbyAll.id == "nearbyAll")
        #expect(AppSheetRoute.recentStopsAll.id == "recentStopsAll")
        #expect(AppSheetRoute.bookmarksAll.id == "bookmarksAll")
        #expect(AppSheetRoute.tripPlanner.id == "tripPlanner")
        #expect(AppSheetRoute.routePicker.id == "routePicker")
        #expect(AppSheetRoute.more.id == "more")
        #expect(AppSheetRoute.settings.id == "settings")
    }

    @Test func `Id embeds associated values`() throws {
        #expect(AppSheetRoute.stopDetails(stopID: "1_75403").id == "stopDetails-1_75403")
        #expect(AppSheetRoute.tripDetails(tripID: "trip_42").id == "tripDetails-trip_42")
        let route = try Fixtures.createRoute(id: "route_8")
        #expect(AppSheetRoute.currentTrip(route: route).id == "currentTrip-route_8")
        #expect(AppSheetRoute.transitAlert(alertID: "alert_99").id == "transitAlert-alert_99")
    }

    @Test func `Id differs between instances of same case`() {
        let a = AppSheetRoute.stopDetails(stopID: "1_75403")
        let b = AppSheetRoute.stopDetails(stopID: "1_75404")
        #expect(a.id != b.id)
    }

    // MARK: - Stacking preference

    @Test func `Prefers stacking base layer routes`() {
        #expect(AppSheetRoute.home.prefersStacking == false)
        #expect(AppSheetRoute.search.prefersStacking == false)
        #expect(AppSheetRoute.routePicker.prefersStacking == false)
    }

    @Test func `Prefers stacking stacked layer routes`() throws {
        #expect(AppSheetRoute.stopDetails(stopID: "1").prefersStacking == true)
        #expect(AppSheetRoute.tripPlanner.prefersStacking == true)
        #expect(AppSheetRoute.tripDetails(tripID: "t").prefersStacking == true)
        let route = try Fixtures.createRoute(id: "r")
        #expect(AppSheetRoute.currentTrip(route: route).prefersStacking == true)
        #expect(AppSheetRoute.transitAlert(alertID: "a").prefersStacking == true)
        #expect(AppSheetRoute.more.prefersStacking == true)
        #expect(AppSheetRoute.nearbyAll.prefersStacking == true)
        #expect(AppSheetRoute.recentStopsAll.prefersStacking == true)
        #expect(AppSheetRoute.bookmarksAll.prefersStacking == true)
        #expect(AppSheetRoute.settings.prefersStacking == true)
    }

    // MARK: - Detent configuration

    @Test func `Home detent starts at small and offers all three`() {
        let config = AppSheetRoute.home.detentConfiguration
        #expect(config.detents == [.height(80), .medium, AppSheetRoute.largeDetent])
        #expect(config.initialDetent == .height(80))
        #expect(config.showDragIndicator == true)
        #expect(config.isDismissDisabled == true)
    }

    @Test func `Home detent flips to full screen at large detent`() {
        // `upThrough:` isn't honored with custom `.height` detents, so the home
        // route flips background interaction to `.disabled` only when parked at
        // `largeDetent` via `fullScreenDetent`.
        let config = AppSheetRoute.home.detentConfiguration
        #expect(config.fullScreenDetent == AppSheetRoute.largeDetent)
    }

    @Test func `Search detent is full large and dismiss disabled`() {
        let config = AppSheetRoute.search.detentConfiguration
        #expect(config.detents == [.large])
        #expect(config.initialDetent == .large)
        #expect(config.isDismissDisabled == true)
        #expect(config.fullScreenDetent == nil)
    }

    @Test func `Stacked all list routes share large and allow dismiss`() {
        // These all-list routes are stacked sheets, so the OS owns dismissal
        // and `isDismissDisabled` must be `false` for `truncateStacked` to stay
        // in sync with the drag-down gesture.
        for route in [AppSheetRoute.nearbyAll, .recentStopsAll, .bookmarksAll] {
            let config = route.detentConfiguration
            #expect(config.detents == [.large])
            #expect(config.initialDetent == .large)
            #expect(config.isDismissDisabled == false)
            #expect(config.fullScreenDetent == nil)
        }
    }

    @Test func `Stop details detent starts medium and is interactively dismissible`() {
        let config = AppSheetRoute.stopDetails(stopID: "1").detentConfiguration
        #expect(config.detents == [.medium, .large])
        #expect(config.initialDetent == .medium)
        #expect(config.isDismissDisabled == false)
        #expect(config.fullScreenDetent == nil)
    }

    @Test func `Stacked detail routes share large start and allow dismiss`() throws {
        let currentTripRoute = try Fixtures.createRoute(id: "r")
        let routes: [AppSheetRoute] = [
            .tripPlanner,
            .tripDetails(tripID: "t"),
            .routePicker,
            .currentTrip(route: currentTripRoute),
            .transitAlert(alertID: "a"),
            .more,
            .settings
        ]

        for route in routes {
            let config = route.detentConfiguration
            #expect(config.detents == [.medium, .large])
            #expect(config.initialDetent == .large)
            #expect(config.isDismissDisabled == false)
            #expect(config.fullScreenDetent == nil)
        }
    }

    @Test func `All routes show drag indicator`() throws {
        // No route currently opts out of the drag indicator; this guards against
        // an accidental flip when adding a new case.
        let currentTripRoute = try Fixtures.createRoute(id: "r")
        let routes: [AppSheetRoute] = [
            .home, .search, .nearbyAll, .recentStopsAll, .bookmarksAll,
            .stopDetails(stopID: "1"), .tripPlanner, .tripDetails(tripID: "t"),
            .routePicker, .currentTrip(route: currentTripRoute), .transitAlert(alertID: "a"),
            .more, .settings
        ]
        for route in routes {
            #expect(route.detentConfiguration.showDragIndicator == true)
        }
    }

    @Test func `Large detent is fractioned just below full screen`() {
        #expect(AppSheetRoute.largeDetent == .fraction(0.99))
    }

    @Test func `Home collapsed height matches map bottom inset`() {
        // Shared with `MapPanelRootView` so the map's bottom safe-area padding
        // matches the collapsed sheet — keep the constant pinned.
        #expect(AppSheetRoute.homeCollapsedHeight == 80)
    }

    // MARK: - SheetDetentConfiguration defaults

    @Test func `Sheet detent configuration applies defaults for optional fields`() {
        let config = SheetDetentConfiguration(
            detents: [.medium],
            initialDetent: .medium,
            isDismissDisabled: false
        )
        #expect(config.showDragIndicator == true)
        #expect(config.fullScreenDetent == nil)
    }

    // MARK: - fullScreenDetent override

    /// The home config flips background interaction to `.disabled` at
    /// `largeDetent` — the regression guard for the previously-dead override.
    /// The override predicate is the testable surface here;
    /// `PresentationBackgroundInteraction` is opaque and can't be compared
    /// directly, so the modifier itself stays out of the test.
    @Test func `Should disable background for full screen home at large detent is true`() {
        let config = AppSheetRoute.home.detentConfiguration
        #expect(config.shouldDisableBackgroundForFullScreen(at: AppSheetRoute.largeDetent) == true)
    }

    @Test func `Should disable background for full screen home below large detent is false`() {
        let config = AppSheetRoute.home.detentConfiguration
        #expect(config.shouldDisableBackgroundForFullScreen(at: .medium) == false)
        #expect(config.shouldDisableBackgroundForFullScreen(at: .height(AppSheetRoute.homeCollapsedHeight)) == false)
    }

    @Test func `Should disable background for full screen is false when full screen detent not configured`() {
        // `.search` does not set `fullScreenDetent`, so the predicate must
        // return `false` regardless of the current detent.
        let config = AppSheetRoute.search.detentConfiguration
        #expect(config.shouldDisableBackgroundForFullScreen(at: .large) == false)
        #expect(config.shouldDisableBackgroundForFullScreen(at: .medium) == false)
    }

    // MARK: - Hashable / Equatable

    @Test func `Equality same case same associated value are equal`() {
        #expect(AppSheetRoute.stopDetails(stopID: "1_1") == AppSheetRoute.stopDetails(stopID: "1_1"))
        #expect(AppSheetRoute.tripDetails(tripID: "t") == AppSheetRoute.tripDetails(tripID: "t"))
    }

    @Test func `Equality different associated values are not equal`() throws {
        #expect(AppSheetRoute.stopDetails(stopID: "1_1") != AppSheetRoute.stopDetails(stopID: "1_2"))
        let route1 = try Fixtures.createRoute(id: "r1")
        let route2 = try Fixtures.createRoute(id: "r2")
        #expect(AppSheetRoute.currentTrip(route: route1) != AppSheetRoute.currentTrip(route: route2))
    }

    @Test func `Hash consistency for value equal routes`() throws {
        let route1 = try Fixtures.createRoute(id: "r1")
        let route2 = try Fixtures.createRoute(id: "r1")
        let sheetRoute1 = AppSheetRoute.currentTrip(route: route1)
        let sheetRoute2 = AppSheetRoute.currentTrip(route: route2)
        // Two routes with the same ID should hash to the same value
        #expect(sheetRoute1.hashValue == sheetRoute2.hashValue)
    }

    // MARK: - Exhaustiveness guard

    /// Adding a new `AppSheetRoute` case must fail to compile here, forcing
    /// the author to extend the id / stacking / detent tests above.
    private func exhaustivenessGuard(_ route: AppSheetRoute) {
        switch route {
        case .home, .search, .nearbyAll, .recentStopsAll, .bookmarksAll,
             .stopDetails, .tripPlanner, .tripDetails, .routePicker,
             .currentTrip, .transitAlert, .more, .settings:
            break
        }
    }
}
