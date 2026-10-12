//
//  ScheduleViewControllers.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import SwiftUI
import OBAKitCore

/// A UIHostingController wrapper for ScheduleForRouteView
@MainActor
class ScheduleForRouteViewController: UIHostingController<ScheduleForRouteView> {

    /// The route ID displayed by this controller.
    let routeID: RouteID

    /// Creates a new ScheduleForRouteViewController
    /// - Parameters:
    ///   - routeID: The route ID to display the schedule for
    ///   - application: The Application object for service access
    init(routeID: RouteID, application: Application) {
        self.routeID = routeID
        let rootView = ScheduleForRouteView(routeID: routeID, application: application)
        super.init(rootView: rootView)

        modalPresentationStyle = .pageSheet
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// A UIHostingController wrapper for ScheduleForStopView
@MainActor
class ScheduleForStopViewController: UIHostingController<ScheduleForStopView> {

    /// The stop ID displayed by this controller.
    let stopID: StopID

    /// The route ID optionally pre-selected by this controller.
    let routeID: RouteID?

    /// Creates a new ScheduleForStopViewController
    /// - Parameters:
    ///   - stopID: The stop ID to display the schedule for
    ///   - routeID: Optional route ID to pre-select in the schedule view
    ///   - application: The Application object for service access
    init(stopID: StopID, routeID: RouteID? = nil, application: Application) {
        self.stopID = stopID
        self.routeID = routeID
        let rootView = ScheduleForStopView(stopID: stopID, routeID: routeID, application: application)
        super.init(rootView: rootView)

        self.modalPresentationStyle = .pageSheet
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Factory for building schedule view controllers based on regional support and available context.
@MainActor
enum ScheduleViewControllerFactory {

    /// Determines whether a schedule can be presented given regional support and an optional stop ID.
    ///
    /// - Parameters:
    ///   - stopID: The stop ID if one is available.
    ///   - application: The application context.
    /// - Returns: `true` if the current region supports route schedules or a stop ID is available for fallback.
    static func canPresentSchedule(stopID: StopID?, application: Application) -> Bool {
        let supportsRouteSchedule = application.currentRegion?.supportsScheduleForRoute ?? true
        return supportsRouteSchedule || stopID != nil
    }

    /// Creates the appropriate schedule view controller for a route, falling back to a stop schedule
    /// if route schedules are unsupported in the current region.
    ///
    /// - Parameters:
    ///   - routeID: The route to display the schedule for.
    ///   - stopID: Optional stop ID to fall back to when route schedules are unsupported.
    ///   - application: The application context.
    /// - Returns: A configured `UIViewController`, or `nil` if route schedules are unsupported and no stop ID is available.
    static func makeScheduleViewController(
        routeID: RouteID,
        stopID: StopID?,
        application: Application
    ) -> UIViewController? {
        if application.currentRegion?.supportsScheduleForRoute ?? true {
            return ScheduleForRouteViewController(routeID: routeID, application: application)
        } else if let stopID {
            return ScheduleForStopViewController(stopID: stopID, routeID: routeID, application: application)
        } else {
            return nil
        }
    }
}
