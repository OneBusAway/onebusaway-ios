//
//  MapPanelOnDemandPlanner.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import SwiftUI

/// The map panel's half of R11: `TripPlanEmptyFallback` decides whether an empty
/// trip plan gets an on-demand card, and this places it. The classic map does the
/// same in `MapViewController+TripPlanner`.
enum MapPanelOnDemandPlanner {

    /// The panel's fallback: it shares the panel's probe controller, whose dock
    /// draws the card, and uncovers the card through the sheet coordinator.
    static func makeFallback(
        probeController: OnDemandProbeController,
        notificationCenter: NotificationCenter,
        coordinator: SheetCoordinator<AppSheetRoute>
    ) -> TripPlanEmptyFallback {
        let fallback = TripPlanEmptyFallback(probeController: probeController, notificationCenter: notificationCenter)
        fallback.onChange = { [weak coordinator] isShowingCard in
            guard let coordinator else { return }
            fallbackDidChange(isShowingCard: isShowingCard, coordinator: coordinator)
        }
        return fallback
    }

    /// The planner sheet on the stack, topmost first. Only one can be open.
    static func plannerEntry(in entries: [SheetCoordinator<AppSheetRoute>.StackedEntry]) -> (request: TripPlannerRequest, detent: PresentationDetent)? {
        for entry in entries.reversed() {
            if case .tripPlanner(let request) = entry.route {
                return (request, entry.detent)
            }
        }
        return nil
    }

    /// The fallback listens for exactly as long as a planner sheet is open, so
    /// closing it, however the rider does, takes its card away.
    ///
    /// The endpoints are the ones the planner opens with, the same as the classic
    /// map's: the request's origin, or the rider's location when it has none (what
    /// OTPKit fills in), and the request's destination. They only matter when OTPKit's
    /// notification carries no endpoints of its own.
    static func plannerDidChange(to request: TripPlannerRequest?, fallback: TripPlanEmptyFallback, currentLocation: CLLocation?) {
        guard let request else {
            fallback.stop()
            return
        }
        fallback.start(
            origin: TripPlannerEndpoints.origin(explicit: request.origin, currentLocation: currentLocation)?.coordinate,
            destination: TripPlannerEndpoints.destination(from: request.destination)?.coordinate
        )
    }

    /// A card shown under a full-height planner would be covered, so the planner
    /// drops to `.medium`, as the classic map drops its panel to half. A planner the
    /// rider has already lowered stays where it is.
    static func fallbackDidChange(isShowingCard: Bool, coordinator: SheetCoordinator<AppSheetRoute>) {
        guard isShowingCard,
              plannerEntry(in: coordinator.stackedEntries)?.detent == .large else { return }
        coordinator.setStackedDetent(.medium) { route in
            if case .tripPlanner = route { return true }
            return false
        }
    }

    /// Where the dock sits. The planner sheet is stacked over the base sheet, so a
    /// planner card placed on the base sheet, like the map's other cards, would sit
    /// under it: the card rides on the planner sheet instead, and hides while the
    /// planner is at full height and covers the map.
    ///
    /// - Returns: the height to float the dock above, and its opacity. Nil opacity
    ///   keeps the toolbars' own, which fade as the base sheet rises.
    static func dockPlacement(
        dockState: OnDemandDockState,
        plannerDetent: PresentationDetent?,
        sheetHeight: CGFloat,
        halfScreenHeight: CGFloat,
        totalMapHeight: CGFloat
    ) -> (height: CGFloat, opacity: CGFloat?) {
        guard case .planner = dockState, let plannerDetent else { return (sheetHeight, nil) }
        if plannerDetent == .large {
            return (sheetHeight, 0)
        }
        // The planner is never at the home sheet's collapsed detent.
        let plannerHeight = MapPanelBottomPadding.estimatedHeight(
            for: plannerDetent,
            halfScreenHeight: halfScreenHeight,
            totalMapHeight: totalMapHeight,
            homeCollapsedHeight: AppSheetRoute.homeCollapsedHeight
        )
        return (max(sheetHeight, plannerHeight), 1)
    }
}
