//
//  HealthKitSpeedSync.swift
//  OneBusAway
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import HealthKit
import OBAKit
import OBAKitCore

extension SpeedSyncConfiguration {
    /// Reads walking and cycling speed from Apple Health. Compiled only when
    /// `Apps/Shared/healthkit.yml` is included; see the README beside this folder.
    static func healthKit() -> SpeedSyncConfiguration {
        let healthStore = HKHealthStore()
        let appName = Bundle.main.appName

        return SpeedSyncConfiguration(
            walkingProvider: HKHealthStoreWalkingSpeedProvider(healthStore: healthStore),
            bikeProvider: HKHealthStoreBikeSpeedProvider(healthStore: healthStore),
            text: SpeedSyncText(
                toggleTitle: localized(
                    "settings_controller.use_healthkit",
                    "Use Health app data"
                ),
                // App Review (guideline 2.5.1) requires the HealthKit integration to be
                // identified in the UI, not only in the permission sheet.
                walkingFooter: String(format: localized(
                    "settings_controller.walking_speed_section.healthkit_footer_fmt",
                    "%@ can read your walking speed from Apple Health to estimate how long it takes you to reach a stop. It never writes to Health."
                ), appName),
                walkingFailureMessage: localized(
                    "settings_controller.walking_speed.healthkit_unavailable",
                    "Couldn't sync walking speed from Health. Check Settings > Privacy & Security > Health to allow access."
                ),
                bikeFooter: String(format: localized(
                    "settings_controller.bike_mode_section.healthkit_footer_fmt",
                    "%@ can read your cycling speed from Apple Health. It never writes to Health."
                ), appName),
                bikeFailureMessage: localized(
                    "settings_controller.bike_mode.healthkit_unavailable",
                    "Couldn't sync cycling speed from Health. Using a standard biking speed instead."
                )
            )
        )
    }

    private static func localized(_ key: String, _ value: String) -> String {
        Bundle.main.localizedString(forKey: key, value: value, table: "HealthKit")
    }
}
