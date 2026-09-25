//
//  RegionMonitoringLocationManager.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation

/// The part of `CLLocationManager` that arms geofences.
///
/// Split from `LocationManager` because watchOS's `CLLocationManager` has no
/// region monitoring at all: with these four requirements on the base protocol,
/// `CLLocationManager` cannot conform to it there and OBAKitCore does not build
/// for the watch. This file is iOS-only; `LocationManager` is portable.
public protocol RegionMonitoringLocationManager: LocationManager {
    func startMonitoring(for region: CLRegion)
    func stopMonitoring(for region: CLRegion)
    var monitoredRegions: Set<CLRegion> { get }

    /// The largest radius, in meters, this device will actually monitor.
    ///
    /// An oversize region is not silently clamped: Core Location answers it with
    /// `CLError.regionMonitoringFailure`, delivered asynchronously through
    /// `monitoringDidFailFor` and carrying no radius. Reading the limit up front
    /// is what lets a caller clamp deliberately and report it, rather than learn
    /// later that something failed without learning what.
    var maximumRegionMonitoringDistance: CLLocationDistance { get }
}

extension CLLocationManager: RegionMonitoringLocationManager {
    // nop. CLLocationManager already implements all of the protocol methods.
}
