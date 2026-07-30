//
//  Color.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import UIKit
import Testing

private func haveEqualRGBValues(_ actual: UIColor?, _ expected: UIColor?) -> Bool {
    guard
        let actual = actual,
        let expected = expected
    else {
        return false
    }

    if actual == expected {
        return true
    }

    var aR: CGFloat = 0, aG: CGFloat = 0, aB: CGFloat = 0, aA: CGFloat = 0
    var eR: CGFloat = 0, eG: CGFloat = 0, eB: CGFloat = 0, eA: CGFloat = 0

    actual.getRed(&aR, green: &aG, blue: &aB, alpha: &aA)
    expected.getRed(&eR, green: &eG, blue: &eB, alpha: &eA)

    return aR == eR && aG == eG && aB == eB && aA == eA
}

/// Asserts that two colours have identical RGBA components.
///
/// This replaces a Nimble matcher that was *named* `beCloseTo` but never
/// compared approximately — it whacks both colours into RGB space and requires
/// exact component equality. The name says what it does now. Direct `==` is not
/// a substitute: `UIColor` instances built in different colour spaces (notably
/// `UIColor(Color)` vs `UIColor.white`) compare unequal even when their RGBA
/// components match, which is the whole reason this helper exists.
func expectEqualRGB(
    _ actual: UIColor?,
    _ expected: UIColor?,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard haveEqualRGBValues(actual, expected) else {
        Issue.record(
            "expected RGB values of \(String(describing: actual)) to equal those of \(String(describing: expected))",
            sourceLocation: sourceLocation
        )
        return
    }
}
