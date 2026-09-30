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
final class ReportProblemCopyTests {

    @Test func testStopProblemHeader() {
        let header = ReportProblemCopy.stopProblemHeader
        // The default fallback in English should be returned if localized isn't provided
        #expect(header.count > 0)
        #expect(header.lowercased().contains("problem"))
        #expect(header.lowercased().contains("stop"))
    }

    @Test func testVehicleProblemHeader() {
        let header = ReportProblemCopy.vehicleProblemHeader
        #expect(header.count > 0)
        #expect(header.lowercased().contains("problem"))
        #expect(header.lowercased().contains("trip"))
    }
}
