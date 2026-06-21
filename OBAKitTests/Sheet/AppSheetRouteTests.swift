//
//  AppSheetRouteTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
@testable import OBAKit
@testable import OBAKitCore

/// Pure-enum tests for `AppSheetRoute`: stable identifiers,
/// stacking preference, and per-detent configuration.
final class AppSheetRouteTests: XCTestCase {

    // MARK: - Identifiers

    func test_id_isStableForCaselessRoutes() {
        expect(AppSheetRoute.home.id) == "home"
        expect(AppSheetRoute.search.id) == "search"
        expect(AppSheetRoute.nearbyAll.id) == "nearbyAll"
        expect(AppSheetRoute.recentStopsAll.id) == "recentStopsAll"
        expect(AppSheetRoute.bookmarksAll.id) == "bookmarksAll"
        expect(AppSheetRoute.tripPlanner.id) == "tripPlanner"
        expect(AppSheetRoute.routePicker.id) == "routePicker"
        expect(AppSheetRoute.more.id) == "more"
        expect(AppSheetRoute.settings.id) == "settings"
    }

    func test_id_embedsAssociatedValues() {
        expect(AppSheetRoute.stopDetails(stopID: "1_75403").id) == "stopDetails-1_75403"
        expect(AppSheetRoute.tripDetails(tripID: "trip_42").id) == "tripDetails-trip_42"
        expect(AppSheetRoute.currentTrip(routeID: "route_8").id) == "currentTrip-route_8"
        expect(AppSheetRoute.transitAlert(alertID: "alert_99").id) == "transitAlert-alert_99"
    }

    func test_id_differsBetweenInstancesOfSameCase() {
        let a = AppSheetRoute.stopDetails(stopID: "1_75403")
        let b = AppSheetRoute.stopDetails(stopID: "1_75404")
        expect(a.id) != b.id
    }

    // MARK: - Stacking preference

    func test_prefersStacking_baseLayerRoutes() {
        expect(AppSheetRoute.home.prefersStacking) == false
        expect(AppSheetRoute.search.prefersStacking) == false
        expect(AppSheetRoute.routePicker.prefersStacking) == false
    }

    func test_prefersStacking_stackedLayerRoutes() {
        expect(AppSheetRoute.stopDetails(stopID: "1").prefersStacking) == true
        expect(AppSheetRoute.tripPlanner.prefersStacking) == true
        expect(AppSheetRoute.tripDetails(tripID: "t").prefersStacking) == true
        expect(AppSheetRoute.currentTrip(routeID: "r").prefersStacking) == true
        expect(AppSheetRoute.transitAlert(alertID: "a").prefersStacking) == true
        expect(AppSheetRoute.more.prefersStacking) == true
        expect(AppSheetRoute.nearbyAll.prefersStacking) == true
        expect(AppSheetRoute.recentStopsAll.prefersStacking) == true
        expect(AppSheetRoute.bookmarksAll.prefersStacking) == true
        expect(AppSheetRoute.settings.prefersStacking) == true
    }

    // MARK: - Detent configuration

    func test_homeDetent_startsAtSmallAndOffersAllThree() {
        let config = AppSheetRoute.home.detentConfiguration
        expect(config.detents) == [.height(80), .medium, AppSheetRoute.largeDetent]
        expect(config.initialDetent) == .height(80)
        expect(config.showDragIndicator) == true
        expect(config.isDismissDisabled) == true
    }

    func test_searchDetent_isFullLargeAndDismissDisabled() {
        let config = AppSheetRoute.search.detentConfiguration
        expect(config.detents) == [.large]
        expect(config.initialDetent) == .large
        expect(config.isDismissDisabled) == true
    }

    func test_baseListRoutes_shareSearchConfig() {
        for route in [AppSheetRoute.nearbyAll, .recentStopsAll, .bookmarksAll] {
            let config = route.detentConfiguration
            expect(config.detents) == [.large]
            expect(config.initialDetent) == .large
            expect(config.isDismissDisabled) == true
        }
    }

    func test_stopDetailsDetent_startsMediumAndIsInteractivelyDismissible() {
        let config = AppSheetRoute.stopDetails(stopID: "1").detentConfiguration
        expect(config.detents) == [.medium, .large]
        expect(config.initialDetent) == .medium
        expect(config.isDismissDisabled) == false
    }

    func test_stackedDetailRoutes_shareLargeStartAndAllowDismiss() {
        let routes: [AppSheetRoute] = [
            .tripPlanner,
            .tripDetails(tripID: "t"),
            .routePicker,
            .currentTrip(routeID: "r"),
            .transitAlert(alertID: "a"),
            .more,
            .settings
        ]

        for route in routes {
            let config = route.detentConfiguration
            expect(config.detents) == [.medium, .large]
            expect(config.initialDetent) == .large
            expect(config.isDismissDisabled) == false
        }
    }

    func test_largeDetent_isFractionedJustBelowFullScreen() {
        expect(AppSheetRoute.largeDetent) == .fraction(0.99)
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
