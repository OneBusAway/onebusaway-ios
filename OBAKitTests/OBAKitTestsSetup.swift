//
//  OBAKitTestsSetup.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// The test bundle's `NSPrincipalClass` (see Info.plist and OBAKitTests/project.yml),
/// instantiated once before any test runs.
///
/// It used to raise `Nimble.PollingDefaults.timeout`, which is dead now that no
/// test polls through Nimble — `poll(until:)` in Helpers/Polling.swift takes its
/// own `timeout:` per call site. The class itself has to stay: removing it would
/// leave Info.plist pointing at a class that no longer exists.
class OBAKitTestsSetup: NSObject {
    override init() {
        super.init()
    }
}
