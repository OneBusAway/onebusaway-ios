//
//  OBAKitTestsSetup.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 1/31/20.
//

import Foundation
import Nimble

class OBAKitTestsSetup: NSObject {
    override init() {
        super.init()

        Nimble.AsyncDefaults.Timeout = 5.0
    }
}
