//
//  OBAMockHeading.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation

open class OBAMockHeading: CLHeading {

    var _magneticHeading: CLLocationDirection = 0.0
    open override var magneticHeading: CLLocationDirection {
        return _magneticHeading
    }

    var _trueHeading: CLLocationDirection = 0.0
    open override var trueHeading: CLLocationDirection {
        return _trueHeading
    }

    var _headingAccuracy: CLLocationDirection = 0.0
    open override var headingAccuracy: CLLocationDirection {
        return _headingAccuracy
    }

    var _timestamp: Date
    open override var timestamp: Date {
        return _timestamp
    }

    public init(heading: CLLocationDirection, timestamp: Date = Date()) {
        self._magneticHeading = heading
        self._trueHeading = heading
        self._timestamp = timestamp

        super.init()
    }

    public required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    open override var debugDescription: String {
        return "wtf is wrong with this class?"
    }
}
