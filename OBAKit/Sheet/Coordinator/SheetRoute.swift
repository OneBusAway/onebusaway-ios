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
nonisolated struct SheetDetentConfiguration {
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
        // `initialDetent` and `fullScreenDetent` must live inside `detents` —
        // both are matched by `==` against the current selection, so a stray
        // value would be silently dead config (initialDetent never seeded,
        // fullScreenDetent never matched). Catch the slip where it happens.
        precondition(detents.contains(initialDetent), "initialDetent must be a member of detents.")
        if let fullScreenDetent {
            precondition(detents.contains(fullScreenDetent), "fullScreenDetent must be a member of detents.")
        }

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
nonisolated protocol SheetRouteable: Identifiable, Hashable {
    var detentConfiguration: SheetDetentConfiguration { get }
    /// When `true`, `SheetCoordinator.push(_:)` routes this case to the stacked
    /// layer (a second sheet over the base sheet); otherwise content-swap.
    var prefersStacking: Bool { get }
}

// MARK: - AppSheetRoute

/// All navigable destinations within the floating sheet.
nonisolated enum AppSheetRoute: SheetRouteable {
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
    case currentTrip(route: Route)
    case transitAlert(alertID: String)

    case more
    case settings

}

nonisolated extension AppSheetRoute {
    // MARK: Identifiable

    /// Case-name prefix only — `String(describing:)` for a case-less enum value
    /// renders the case name (e.g. `"home"`); for cases with associated values
    /// it includes the payload, which we strip and reapply per-case below so
    /// each suffix can be intentionally formatted.
    private var caseName: String {
        let mirror = Mirror(reflecting: self)
        if let label = mirror.children.first?.label {
            return label
        }
        // No associated value → `String(describing:)` is already just the case name.
        return String(describing: self)
    }

    /// Stable identifier used by `Identifiable` and the sheet coordinator.
    /// Prefix is derived mechanically from the case name (typo-proof against
    /// hand-keyed strings); only the associated-value suffix is hand-written
    /// per case so each can pick its own formatting.
    var id: String {
        switch self {
        case .home, .search, .nearbyAll, .recentStopsAll, .bookmarksAll,
             .tripPlanner, .routePicker, .more, .settings:
            return caseName
        case .stopDetails(let stopID):
            return "\(caseName)-\(stopID)"
        case .tripDetails(let tripID):
            return "\(caseName)-\(tripID)"
        case .currentTrip(let route):
            return "\(caseName)-\(route.id)"
        case .transitAlert(let alertID):
            return "\(caseName)-\(alertID)"
        }
    }

    // MARK: Hashable / Equatable

    static func == (lhs: AppSheetRoute, rhs: AppSheetRoute) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

nonisolated extension AppSheetRoute {
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

nonisolated extension AppSheetRoute {

    /// "Almost-full" detent used as the largest stop for the home sheet and
    /// other content-swap routes. `.fraction(0.99)` rather than `.large`
    /// preserves the floating-card look (a sliver of map remains visible at
    /// the top edge) and lets `fullScreenDetent` reliably match — `.large`
    /// reports through a different detent identity that `==` comparison can't
    /// catch.
    static var largeDetent: PresentationDetent {
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
