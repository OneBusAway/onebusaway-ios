//
//  SpeedSync.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Supplies a rider's measured speed to `WalkingSpeedManager` or `BikeModeManager`.
public protocol SpeedProviding {
    /// `true` when this device can supply the speed.
    var isAvailable: Bool { get }

    /// Requests read authorization.
    /// May complete successfully even when the user denies; denial is detected by the absence of samples.
    func requestAuthorization() async throws

    /// Returns the rider's speed (m/s) over the last 30 days, or `nil` if none exists or the query fails.
    /// Does not apply range validation; the caller decides what counts as a usable sample.
    func fetchSpeed() async -> Double?
}

/// The Settings copy for speed sync. The app supplies it with the providers, because
/// it names the data source.
public struct SpeedSyncText {
    public let toggleTitle: String
    public let walkingFooter: String
    public let walkingFailureMessage: String
    public let bikeFooter: String
    public let bikeFailureMessage: String

    public init(
        toggleTitle: String,
        walkingFooter: String,
        walkingFailureMessage: String,
        bikeFooter: String,
        bikeFailureMessage: String
    ) {
        self.toggleTitle = toggleTitle
        self.walkingFooter = walkingFooter
        self.walkingFailureMessage = walkingFailureMessage
        self.bikeFooter = bikeFooter
        self.bikeFailureMessage = bikeFailureMessage
    }
}

/// An app's optional source of measured speeds, set on `AppConfig.speedSync`. Without
/// one, Settings offers only the manual walking speed picker. OBAKit deliberately knows
/// nothing about where the speeds come from.
public struct SpeedSyncConfiguration {
    public let walkingProvider: any SpeedProviding
    public let bikeProvider: any SpeedProviding
    public let text: SpeedSyncText

    public init(walkingProvider: any SpeedProviding, bikeProvider: any SpeedProviding, text: SpeedSyncText) {
        self.walkingProvider = walkingProvider
        self.bikeProvider = bikeProvider
        self.text = text
    }

    /// Whether Settings should offer the switches on this device.
    var isAvailable: Bool {
        walkingProvider.isAvailable && bikeProvider.isAvailable
    }
}
