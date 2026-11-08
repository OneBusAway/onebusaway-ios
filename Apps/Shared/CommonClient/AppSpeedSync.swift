//
//  AppSpeedSync.swift
//  OneBusAway
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKit

extension SpeedSyncConfiguration {
    /// This build's speed sync source, for `AppConfig.speedSync`. `nil` unless
    /// `Apps/Shared/healthkit.yml` is included, which defines `OBA_HEALTHKIT` and
    /// compiles the sources it uses. Every app sets it, so the compile condition
    /// lives here rather than in each AppDelegate.
    static var appDefault: SpeedSyncConfiguration? {
        #if OBA_HEALTHKIT
        .healthKit()
        #else
        nil
        #endif
    }
}
