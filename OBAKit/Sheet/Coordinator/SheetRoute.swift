//
//  SheetRoute.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

// MARK: - SheetDetentConfiguration

/// Per-route configuration for detent behaviour, drag indicator, dismiss lock, and background interaction.
struct SheetDetentConfiguration {
    let detents: Set<PresentationDetent>
    let initialDetent: PresentationDetent
    let showDragIndicator: Bool
    let isDismissDisabled: Bool
    let backgroundInteraction: PresentationBackgroundInteraction

    /// When set, background interaction is forced to `.disabled` while the sheet
    /// is parked at this detent — useful for the iPhone-landscape case where the
    /// sheet covers the full screen and nothing remains behind it to interact
    /// with. The `upThrough:` form of `PresentationBackgroundInteraction` isn't
    /// honored with custom `.height` detents, hence the explicit field.
    let fullScreenDetent: PresentationDetent?

    init(
        detents: Set<PresentationDetent>,
        initialDetent: PresentationDetent,
        showDragIndicator: Bool = true,
        isDismissDisabled: Bool,
        backgroundInteraction: PresentationBackgroundInteraction = .enabled(upThrough: .medium),
        fullScreenDetent: PresentationDetent? = nil
    ) {
        self.detents = detents
        self.initialDetent = initialDetent
        self.showDragIndicator = showDragIndicator
        self.isDismissDisabled = isDismissDisabled
        self.backgroundInteraction = backgroundInteraction
        self.fullScreenDetent = fullScreenDetent
    }
}

// MARK: - SheetRouteable

/// Protocol that all sheet route enums must conform to.
/// Each case provides detent configuration and a stacking preference.
/// ViewModel construction lives in `AppSheetViewFactory`, not on the route itself.
protocol SheetRouteable: Identifiable, Hashable {
    var detentConfiguration: SheetDetentConfiguration { get }
    /// When `true`, `SheetCoordinator.push(_:)` routes this case to the stacked
    /// layer (a second sheet over the base sheet); otherwise content-swap.
    var prefersStacking: Bool { get }
}

// MARK: - AppSheetRoute

/// All navigable destinations within the floating sheet.
enum AppSheetRoute: SheetRouteable {
    // Base layer
    case home
    case search
    case nearbyAll
    case recentStopsAll
    case bookmarksAll

    // Stacked layer
    case stopDetails(stopID: Stop.ID)
    case tripPlanner
    case tripDetails(tripID: TripIdentifier)
    case routePicker
    case currentTrip(routeID: RouteID)
    case transitAlert(alertID: String)

    case more
    case settings

}

extension AppSheetRoute {
    // MARK: Identifiable

    var id: String {
        switch self {
        case .home:
            return "home"
        case .search:
            return "search"
        case .nearbyAll:
            return "nearbyAll"
        case .recentStopsAll:
            return "recentStopsAll"
        case .bookmarksAll:
            return "bookmarksAll"
        case .stopDetails(let stopID):
            return "stopDetails-\(stopID)"
        case .tripPlanner:
            return "tripPlanner"
        case .tripDetails(let tripID):
            return "tripDetails-\(tripID)"
        case .routePicker:
            return "routePicker"
        case .currentTrip(let routeID):
            return "currentTrip-\(routeID)"
        case .transitAlert(let alertID):
            return "transitAlert-\(alertID)"
        case .more:
            return "more"
        case .settings:
            return "settings"
        }
    }
}

extension AppSheetRoute {
    /// Detail destinations prefer the stacked layer so the base sheet peeks beneath.
    var prefersStacking: Bool {
        switch self {
        case .stopDetails, .tripPlanner, .tripDetails, .currentTrip, .transitAlert, .more, .nearbyAll, .recentStopsAll, .bookmarksAll, .settings:
            return true
        case .home, .search, .routePicker:
            return false
        }
    }
}

extension AppSheetRoute {

    static var `largeDetent`: PresentationDetent {
        return .fraction(0.99)
    }

    /// Height of the home sheet's smallest detent. Shared by `MapPanelRootView`
    /// so the map's bottom safe-area padding matches the collapsed sheet.
    static let homeCollapsedHeight: CGFloat = 80

    var detentConfiguration: SheetDetentConfiguration {
        switch self {
        case .home:
            // Keep background interaction enabled at small/medium detents so the
            // map and its overlays remain tappable. `upThrough:` isn't honored
            // with custom `.height` detents, so `fullScreenDetent` flips
            // background interaction to `.disabled` only when the sheet is
            // parked at `largeDetent` (covers ~the full screen).
            return SheetDetentConfiguration(
                detents: [.height(AppSheetRoute.homeCollapsedHeight), .medium, AppSheetRoute.largeDetent],
                initialDetent: .height(AppSheetRoute.homeCollapsedHeight),
                isDismissDisabled: true,
                backgroundInteraction: .enabled,
                fullScreenDetent: AppSheetRoute.largeDetent
            )
        case .search:
            // Base-layer: dismiss is locked so the user pops via the back affordance,
            // not by dragging the sheet off-screen.
            return SheetDetentConfiguration(
                detents: [.large],
                initialDetent: .large,
                isDismissDisabled: true,
                backgroundInteraction: .disabled
            )
        case .nearbyAll, .recentStopsAll, .bookmarksAll:
            // Stacked-layer: the OS owns dismissal so storage stays in sync with
            // the drag-down gesture via `truncateStacked`.
            return SheetDetentConfiguration(
                detents: [.large],
                initialDetent: .large,
                isDismissDisabled: false,
                backgroundInteraction: .disabled
            )
        case .stopDetails:
            return SheetDetentConfiguration(
                detents: [.medium, .large],
                initialDetent: .medium,
                isDismissDisabled: false
            )
        case .tripPlanner, .tripDetails, .routePicker, .currentTrip, .transitAlert, .more, .settings:
            return SheetDetentConfiguration(
                detents: [.medium, .large],
                initialDetent: .large,
                isDismissDisabled: false
            )
        }
    }

}
