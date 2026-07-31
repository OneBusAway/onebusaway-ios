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

/// Immutable after `init`, which is what makes the `@unchecked Sendable` below
/// honest: every stored property is a `let`, and the class is `final` so no
/// subclass can add mutable state and silently inherit the promise. Needed
/// because `TestData.mockHeading` is a shared static.
// `nonisolated`: overrides nonisolated CLHeading members, which the target's
// main-actor default isolation would conflict with.
public final nonisolated class OBAMockHeading: CLHeading, @unchecked Sendable {

    let _magneticHeading: CLLocationDirection
    public override var magneticHeading: CLLocationDirection {
        return _magneticHeading
    }

    let _trueHeading: CLLocationDirection
    public override var trueHeading: CLLocationDirection {
        return _trueHeading
    }

    let _headingAccuracy: CLLocationDirection = 0.0
    public override var headingAccuracy: CLLocationDirection {
        return _headingAccuracy
    }

    let _timestamp: Date
    public override var timestamp: Date {
        return _timestamp
    }

    public init(heading: CLLocationDirection, timestamp: Date = Date()) {
        self._magneticHeading = heading
        self._trueHeading = heading
        self._timestamp = timestamp

        super.init()
    }

    public required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override var debugDescription: String {
        return "wtf is wrong with this class?"
    }

    /// `CLHeading`'s own `description` reads the raw magnetometer components
    /// (`x`/`y`/`z`), which this mock does not implement — reaching it segfaults.
    /// Swift Testing reflects the values in a *failing* `#expect`, so without
    /// this override any assertion that touches a mock heading turns a clean
    /// test failure into a crashed test run.
    public override var description: String {
        return "OBAMockHeading(magnetic: \(_magneticHeading), true: \(_trueHeading))"
    }
}
