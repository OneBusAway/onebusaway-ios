//
//  Matchers.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 12/9/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import XCTest
import Nimble

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

/// Whacks everything into the RGB space and does a brute-force comparison of their RGB values.
///
/// - Parameter expectedValue: The expected value of this expression.
/// - Returns: A predicate
public func beCloseTo(_ expectedValue: UIColor) -> Predicate<UIColor> {
    return Predicate.define { actualExpression in
        let errorMessage = "be close to <\(stringify(expectedValue))>"
        let actualValue = try actualExpression.evaluate()

        return PredicateResult(
            bool: haveEqualRGBValues(actualValue, expectedValue),
            message: .expectedCustomValueTo(errorMessage, "<\(stringify(actualValue))>")
        )
    }
}
