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
/// identical to Nimble's, so *that* conversion couldn't change any test's
/// verdict: the default tolerance is 0.0001 and the comparison is **strict**
/// (`<`, not `<=`), matching `abs(actual - expected) < delta` in Nimble's
/// `Matchers/BeCloseTo.swift`.
///
/// That strictness is worth knowing at the call sites converted from
/// `XCTAssertEqual(_:_:accuracy:)`, which failed on `difference > accuracy` —
/// i.e. a difference exactly equal to the tolerance passed there and fails
/// here. No current call site sits on that boundary, and tightening was the
/// safe direction to differ in, but a test written to sit exactly on its
/// tolerance would need `within:` nudged.
///
/// `actual` is optional so that call sites reading through an optional chain
/// (`vehicle.location?.coordinate.latitude`) work unchanged; `nil` fails, as it
/// did under Nimble.
/// - Parameter comment: Optional context, carried over from the message
///   argument that `XCTAssertEqual(_:_:accuracy:_:)` accepted.
func expectClose(
    _ actual: Double?,
    _ expected: Double,
    within delta: Double = defaultDelta,
    _ comment: Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    func record(_ description: String) {
        let detail = comment.map { "\($0.rawValue) — " } ?? ""
        Issue.record("\(detail)\(description)", sourceLocation: sourceLocation)
    }

    guard let actual else {
        record("expected a value close to \(expected), got nil")
        return
    }

    let difference = abs(actual - expected)
    guard difference < delta else {
        record("expected \(actual) to be within \(delta) of \(expected), but it is off by \(difference)")
        return
    }
}

/// Date-comparing variant, matching Nimble's `NMBDoubleConvertible` overload —
/// it compared `timeIntervalSinceReferenceDate`, so this does too.
func expectClose(
    _ actual: Date?,
    _ expected: Date,
    within delta: TimeInterval = defaultDelta,
    _ comment: Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    expectClose(
        actual?.timeIntervalSinceReferenceDate,
        expected.timeIntervalSinceReferenceDate,
        within: delta,
        comment,
        sourceLocation: sourceLocation
    )
}
