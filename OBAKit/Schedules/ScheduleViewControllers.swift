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
class ScheduleForRouteViewController: UIHostingController<ScheduleForRouteView> {

    /// Creates a new ScheduleForRouteViewController
    /// - Parameters:
    ///   - routeID: The route ID to display the schedule for
    ///   - application: The Application object for service access
    init(routeID: RouteID, application: Application) {
        let rootView = ScheduleForRouteView(routeID: routeID, application: application)
        super.init(rootView: rootView)

        // Configure modal presentation
        modalPresentationStyle = .pageSheet
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// A UIHostingController wrapper for ScheduleForStopView
class ScheduleForStopViewController: UIHostingController<ScheduleForStopView> {

    /// Creates a new ScheduleForStopViewController
    /// - Parameters:
    ///   - stopID: The stop ID to display the schedule for
    ///   - application: The Application object for service access
    init(stopID: StopID, application: Application) {
        let rootView = ScheduleForStopView(stopID: stopID, application: application)
        super.init(rootView: rootView)

        self.modalPresentationStyle = .pageSheet
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
