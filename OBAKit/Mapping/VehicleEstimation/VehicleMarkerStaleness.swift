//
//  VehicleMarkerStaleness.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreGraphics
import Foundation
import OBAKitCore

/// How a vehicle marker shows the age of the fix its estimate came from. Shared by
/// `PulsingVehicleAnnotationView` and the panel's `TripVehicleMarker`.
///
/// - A fresh estimate looks as markers always have.
/// - Past `agingStart`, a translucent halo grows with the fix's age and the pulse
///   slows: the vehicle could be anywhere in a widening stretch of road.
/// - Frozen at the horizon, the marker fades, stops pulsing and drops its heading.
enum VehicleMarkerStaleness: Equatable {
    case live
    /// `fraction` runs from 0 at `agingStart` to 1 at the horizon.
    case aging(fraction: Double)
    case frozen

    static let agingStart: TimeInterval = 45
    static let maximumHaloDiameter: CGFloat = 120
    /// The slowest pulse, at the horizon. Quantized so a 1 Hz tick changes it, and
    /// rebuilds the pulse layers, a handful of times rather than every second.
    static let maximumPulseDelay: TimeInterval = 3
    static let frozenAlpha: CGFloat = 0.6

    init(estimate: VehicleEstimate?, horizon: TimeInterval = VehicleEstimationTunables.default.horizon) {
        guard let estimate else {
            self = .live
            return
        }
        switch estimate.mode {
        case .raw:
            self = .live
        case .frozen:
            self = .frozen
        case .estimated, .holding:
            guard estimate.fixAge > Self.agingStart, horizon > Self.agingStart else {
                self = .live
                return
            }
            let fraction = min((estimate.fixAge - Self.agingStart) / (horizon - Self.agingStart), 1)
            // Quantized to tenths, for the same reason as the pulse.
            self = .aging(fraction: (fraction * 10).rounded(.up) / 10)
        }
    }

    var haloDiameter: CGFloat {
        guard case let .aging(fraction) = self else { return 0 }
        return Self.maximumHaloDiameter * CGFloat(fraction)
    }

    var pulseDelay: TimeInterval {
        switch self {
        case .live: 0
        case let .aging(fraction): Self.maximumPulseDelay * fraction
        case .frozen: .infinity
        }
    }

    var alpha: CGFloat {
        self == .frozen ? Self.frozenAlpha : 1
    }

    var showsHeading: Bool {
        self != .frozen
    }
}
