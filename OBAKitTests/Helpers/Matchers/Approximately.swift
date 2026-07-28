//
//  Approximately.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing

/// Nimble's `DefaultDelta`, preserved so converted call sites keep their exact
/// tolerance. Every `beCloseTo` here that didn't pass `within:` used this.
let defaultDelta: Double = 0.0001

/// Asserts that `actual` is within `delta` of `expected`.
///
/// Replacement for Nimble's `beCloseTo`. The semantics are deliberately
/// identical to Nimble's so the conversion couldn't change any test's verdict:
/// the default tolerance is 0.0001 and the comparison is **strict** (`<`, not
/// `<=`), matching `abs(actual - expected) < delta` in Nimble's
/// `Matchers/BeCloseTo.swift`.
///
/// `actual` is optional so that call sites reading through an optional chain
/// (`vehicle.location?.coordinate.latitude`) work unchanged; `nil` fails, as it
/// did under Nimble.
func expectClose(
    _ actual: Double?,
    _ expected: Double,
    within delta: Double = defaultDelta,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard let actual else {
        Issue.record(
            "expected a value close to \(expected), got nil",
            sourceLocation: sourceLocation
        )
        return
    }

    let difference = abs(actual - expected)
    guard difference < delta else {
        Issue.record(
            "expected \(actual) to be within \(delta) of \(expected), but it is off by \(difference)",
            sourceLocation: sourceLocation
        )
        return
    }
}

/// Date-comparing variant, matching Nimble's `NMBDoubleConvertible` overload —
/// it compared `timeIntervalSinceReferenceDate`, so this does too.
func expectClose(
    _ actual: Date?,
    _ expected: Date,
    within delta: TimeInterval = defaultDelta,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    expectClose(
        actual?.timeIntervalSinceReferenceDate,
        expected.timeIntervalSinceReferenceDate,
        within: delta,
        sourceLocation: sourceLocation
    )
}
