//
//  ReportProblemCopyTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
@testable import OBAKit

@Suite(.serialized)
@MainActor
final class ReportProblemCopyTests {

    @Test func `Stop problem header matches the English catalog`() {
        // Asserting the exact literal catches missing keys and prevents
        // test drift if both the copy property and test evaluate the same key.
        #expect(ReportProblemCopy.stopProblemHeader == "Problem with the Stop")
    }

    @Test func `Vehicle problem header matches the English catalog`() {
        #expect(ReportProblemCopy.vehicleProblemHeader == "Problem with a Trip")
    }
}
