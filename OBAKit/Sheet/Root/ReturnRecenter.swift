//
//  ReturnRecenter.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import OBAKitCore

/// Whether the map panel re-centers on the rider when the app comes back, as
/// the UIKit map does in `MapViewController.applicationDidBecomeActive`: after
/// ten minutes away, the rider has likely moved.
enum ReturnRecenter {
    static let minimumAbsence: TimeInterval = 600

    /// - Parameters:
    ///   - absence: How long the app was away.
    ///   - region: The selected region. A rider outside it isn't pulled onto GPS,
    ///     the same rule as launch (#615).
    ///   - location: The rider's location.
    ///   - isShowingSheet: Whether a sheet over home is open. A trip or stop the
    ///     rider left open stays framed.
    static func shouldRecenter(
        absence: TimeInterval,
        region: Region?,
        location: CLLocation?,
        isShowingSheet: Bool
    ) -> Bool {
        guard absence > minimumAbsence, !isShowingSheet, let location else { return false }
        if let region, !region.contains(location: location) { return false }
        return true
    }
}
