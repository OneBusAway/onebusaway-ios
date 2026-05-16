//
//  NavigationIntent.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import OBAKitCore

/// Describes navigation actions a ViewModel wants the UI layer to perform.
/// ViewModels publish these; the UI layer (UIKit VC or SwiftUI view) observes and executes them.
enum NavigationIntent {
    case showStop(Stop)
    case showArrivalDeparture(ArrivalDeparture)
    case showAlert(TransitAlertDataListViewModel)
    case showSchedule
    case showNearbyStops(CLLocationCoordinate2D)
}
