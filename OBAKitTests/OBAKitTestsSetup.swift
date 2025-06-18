//
//  OBAKitTestsSetup.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Nimble

class OBAKitTestsSetup: NSObject {
    override init() {
        super.init()

        Nimble.PollingDefaults.timeout = .seconds(5)
    }
}
