//
//  StopEstimationHarness.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
@testable import OBAKit
@testable import OBAKitCore

/// A `StopVehicleEstimation` on test clocks, for both of a stop's maps: every shape
/// is `EstimationFixtures.straightLine()`, and every trip's schedule runs it at a
/// scheduled 10 m/s.
@MainActor
final class StopEstimationHarness {
    typealias F = EstimationFixtures

    actor Counter {
        private(set) var count = 0
        func increment() { count += 1 }
    }

    /// The device's clock; the driver ticks on `clock`.
    var now = EstimationFixtures.t0
    var isEnabled = true
    let clock = TestClock()
    let scheduleFetches = Counter()
    let shapeCache: ShapeCache

    private(set) var estimation: StopVehicleEstimation!

    static let formatters = Formatters(
        locale: Locale(identifier: "en_US"), calendar: Calendar(identifier: .gregorian), themeColors: ThemeColors.shared
    )

    init() {
        let encoded = Polyline(coordinates: F.straightLine().coordinates).encodedPolyline
        shapeCache = ShapeCache { _ in encoded }
        let counter = scheduleFetches
        estimation = StopVehicleEstimation(
            driver: VehicleEstimationDriver(
                isEnabled: { [unowned self] in isEnabled },
                reduceMotion: { false },
                clock: clock,
                now: { [unowned self] in now },
                notificationCenter: NotificationCenter()
            ),
            shapeCache: shapeCache,
            tripSchedules: TripScheduleCache { _ in
                await counter.increment()
                return TripScheduleCache.Schedule(stopTimes: [F.stop(0, at: 0), F.stop(1000, at: 100)], serverTripLength: 1000)
            }
        )
    }

    /// A `tripStatus` JSON moved onto the shape 200 m along, with a fix time of `F.t0`.
    nonisolated static func onShape(_ status: [String: Any]) -> [String: Any] {
        var status = status
        let onShape = F.point(north: 200)
        status["lastKnownLocation"] = ["lat": onShape.latitude, "lon": onShape.longitude]
        status["lastLocationUpdateTime"] = Int64(F.t0.timeIntervalSince1970 * 1000)
        status["totalDistanceAlongTrip"] = 1000.0
        return status
    }
}
