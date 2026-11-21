//
//  StopPageToolbarAccessibilityTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
struct StopPageToolbarAccessibilityTests {

    private func makeToolbar(
        isRefreshing: Bool = false,
        canFilter: Bool = true,
        hasServiceAlerts: Bool = true,
        onDirectionsToHere: (() -> Void)? = nil,
        onDirectionsFromHere: (() -> Void)? = nil,
        isProximityAlertActive: Bool = false,
        onRefresh: @escaping () -> Void = {},
        onSetListFiltered: @escaping (Bool) -> Void = { _ in },
        onSetDepartureFilter: @escaping (ArrivalDepartureFilter) -> Void = { _ in },
        onBookmark: @escaping () -> Void = {},
        onSchedule: @escaping () -> Void = {},
        onServiceAlerts: @escaping () -> Void = {},
        onNearbyStops: @escaping () -> Void = {},
        onWalkingDirections: @escaping () -> Void = {},
        onToggleProximityAlert: @escaping () -> Void = {},
        onReportProblem: @escaping () -> Void = {}
    ) -> StopPageToolbar {
        StopPageToolbar(
            statusText: "Updated: Just Now",
            isRefreshing: isRefreshing,
            isFilterOn: false,
            canFilter: canFilter,
            isListFiltered: false,
            activeDepartureFilter: .all,
            hasServiceAlerts: hasServiceAlerts,
            onRefresh: onRefresh,
            onSetListFiltered: onSetListFiltered,
            onSetDepartureFilter: onSetDepartureFilter,
            onBookmark: onBookmark,
            onSchedule: onSchedule,
            onServiceAlerts: onServiceAlerts,
            onNearbyStops: onNearbyStops,
            onWalkingDirections: onWalkingDirections,
            onDirectionsToHere: onDirectionsToHere,
            onDirectionsFromHere: onDirectionsFromHere,
            isProximityAlertActive: isProximityAlertActive,
            onToggleProximityAlert: onToggleProximityAlert,
            onReportProblem: onReportProblem
        )
    }

    // MARK: - Stable Labels

    @Test func `Toolbar items expose stable accessibility labels`() {
        #expect(StopPageToolbar.refreshAccessibilityLabel == Strings.refresh)
        #expect(StopPageToolbar.bookmarkAccessibilityLabel == "Bookmark")
        #expect(StopPageToolbar.schedulesAccessibilityLabel == Strings.schedules)
        #expect(StopPageToolbar.moreAccessibilityLabel == Strings.more)
    }

    // MARK: - Accessibility Hints & Explanations

    @Test func `Refresh hint explains disabled updating state when active`() {
        let idleToolbar = makeToolbar(isRefreshing: false)
        #expect(idleToolbar.refreshHint == "Refreshes arrival times.")
        #expect(StopPageToolbar.refreshAccessibilityHint(isRefreshing: false) == "Refreshes arrival times.")

        let updatingToolbar = makeToolbar(isRefreshing: true)
        #expect(updatingToolbar.refreshHint == "Arrival times are currently updating.")
        #expect(StopPageToolbar.refreshAccessibilityHint(isRefreshing: true) == "Arrival times are currently updating.")
    }

    @Test func `Bookmark and Schedules expose expected accessibility hints`() {
        let toolbar = makeToolbar()
        #expect(toolbar.bookmarkHint == "Adds a bookmark for this stop.")
        #expect(toolbar.schedulesHint == "Shows schedules for this stop.")
        #expect(toolbar.moreHint == "Shows more options.")
    }

    @Test func `Filter hint explains disabled state on single route stop`() {
        let multiRoute = makeToolbar(canFilter: true)
        #expect(multiRoute.filterHint == "Filters routes at this stop.")
        #expect(StopPageToolbar.filterAccessibilityHint(canFilter: true) == "Filters routes at this stop.")

        let singleRoute = makeToolbar(canFilter: false)
        #expect(singleRoute.filterHint == "Filtering is unavailable because this stop only serves one route.")
        #expect(StopPageToolbar.filterAccessibilityHint(canFilter: false) == "Filtering is unavailable because this stop only serves one route.")
    }

    @Test func `Service alerts hint explains disabled state when no alerts exist`() {
        let withAlerts = makeToolbar(hasServiceAlerts: true)
        #expect(withAlerts.serviceAlertsHint == "Shows service alerts for this stop.")
        #expect(StopPageToolbar.serviceAlertsAccessibilityHint(hasServiceAlerts: true) == "Shows service alerts for this stop.")

        let withoutAlerts = makeToolbar(hasServiceAlerts: false)
        #expect(withoutAlerts.serviceAlertsHint == "No active service alerts for this stop.")
        #expect(StopPageToolbar.serviceAlertsAccessibilityHint(hasServiceAlerts: false) == "No active service alerts for this stop.")
    }

    // MARK: - Disabled State Predicates

    @Test func `Toolbar disabled state predicates match expected inputs`() {
        let active = makeToolbar(isRefreshing: true, canFilter: false, hasServiceAlerts: false)
        #expect(active.isRefreshDisabled)
        #expect(active.isFilterDisabled)
        #expect(active.isServiceAlertsDisabled)

        let idle = makeToolbar(isRefreshing: false, canFilter: true, hasServiceAlerts: true)
        #expect(!idle.isRefreshDisabled)
        #expect(!idle.isFilterDisabled)
        #expect(!idle.isServiceAlertsDisabled)
    }

    // MARK: - Custom Actions Presence

    @Test func `Custom actions include Service Alerts only when alerts exist`() {
        let withAlerts = makeToolbar(hasServiceAlerts: true)
        #expect(withAlerts.customAccessibilityActions.contains { $0.kind == .serviceAlerts })

        let withoutAlerts = makeToolbar(hasServiceAlerts: false)
        #expect(!withoutAlerts.customAccessibilityActions.contains { $0.kind == .serviceAlerts })
    }

    @Test func `Custom actions include Directions to and from Here only when available`() {
        let withoutDirections = makeToolbar(onDirectionsToHere: nil, onDirectionsFromHere: nil)
        #expect(!withoutDirections.customAccessibilityActions.contains { $0.kind == .directionsToHere })
        #expect(!withoutDirections.customAccessibilityActions.contains { $0.kind == .directionsFromHere })

        let withDirections = makeToolbar(
            onDirectionsToHere: {},
            onDirectionsFromHere: {}
        )
        #expect(withDirections.customAccessibilityActions.contains { $0.kind == .directionsToHere })
        #expect(withDirections.customAccessibilityActions.contains { $0.kind == .directionsFromHere })
    }

    @Test func `Proximity alert custom action title reflects armed status`() {
        let inactive = makeToolbar(isProximityAlertActive: false)
        let inactiveAction = inactive.customAccessibilityActions.first { $0.kind == .proximityAlert }
        #expect(inactiveAction?.name == "Alert Me When Nearby")

        let active = makeToolbar(isProximityAlertActive: true)
        let activeAction = active.customAccessibilityActions.first { $0.kind == .proximityAlert }
        #expect(activeAction?.name == "Cancel Nearby Alert")
    }

    @Test func `Standard more items are always present in custom actions`() {
        let toolbar = makeToolbar()
        let kinds = toolbar.customAccessibilityActions.map(\.kind)
        #expect(kinds.contains(.nearbyStops))
        #expect(kinds.contains(.walkingDirections))
        #expect(kinds.contains(.proximityAlert))
        #expect(kinds.contains(.reportProblem))
    }

    // MARK: - Custom Actions Execution

    @Test func `Custom action callbacks execute correctly`() {
        var serviceAlertsCalled = false
        var nearbyStopsCalled = false
        var walkingDirectionsCalled = false
        var directionsToHereCalled = false
        var directionsFromHereCalled = false
        var proximityAlertCalled = false
        var reportProblemCalled = false

        let toolbar = makeToolbar(
            hasServiceAlerts: true,
            onDirectionsToHere: { directionsToHereCalled = true },
            onDirectionsFromHere: { directionsFromHereCalled = true },
            onServiceAlerts: { serviceAlertsCalled = true },
            onNearbyStops: { nearbyStopsCalled = true },
            onWalkingDirections: { walkingDirectionsCalled = true },
            onToggleProximityAlert: { proximityAlertCalled = true },
            onReportProblem: { reportProblemCalled = true }
        )

        for action in toolbar.customAccessibilityActions {
            action.perform()
        }

        #expect(serviceAlertsCalled)
        #expect(nearbyStopsCalled)
        #expect(walkingDirectionsCalled)
        #expect(directionsToHereCalled)
        #expect(directionsFromHereCalled)
        #expect(proximityAlertCalled)
        #expect(reportProblemCalled)
    }

    // MARK: - String Catalog Integrity

    @Test func `Toolbar accessibility strings exist in English catalog`() throws {
        guard let path = Bundle.obaKit.path(forResource: "en", ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            Issue.record("English bundle not found")
            return
        }

        let keys = [
            "stop_page.toolbar.bookmark.hint": "Adds a bookmark for this stop.",
            "stop_page.toolbar.filter.disabled_hint": "Filtering is unavailable because this stop only serves one route.",
            "stop_page.toolbar.filter.hint": "Filters routes at this stop.",
            "stop_page.toolbar.more.hint": "Shows more options.",
            "stop_page.toolbar.refresh.hint": "Refreshes arrival times.",
            "stop_page.toolbar.refresh.updating_hint": "Arrival times are currently updating.",
            "stop_page.toolbar.schedules.hint": "Shows schedules for this stop.",
            "stop_page.toolbar.service_alerts.disabled_hint": "No active service alerts for this stop.",
            "stop_page.toolbar.service_alerts.hint": "Shows service alerts for this stop."
        ]

        for (key, expectedValue) in keys {
            let localized = bundle.localizedString(forKey: key, value: "MISSING", table: nil)
            #expect(localized != "MISSING", "\(key) is missing from the English catalog")
            #expect(localized == expectedValue, "\(key) has unexpected translation in English catalog")
        }
    }
}
