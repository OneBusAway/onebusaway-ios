//
//  OBAAppIntentsPackage.swift
//  App
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import AppIntents
import OBAKit

/// App-target wrapper so Shortcuts indexes intents defined in OBAKit.
/// See `OBAKitAppIntentsPackage` and docs/shortcut-live-activity.md.
struct OBAAppIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [OBAKitAppIntentsPackage.self]
    }
}
