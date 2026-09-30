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

    private func englishBundle() -> Bundle {
        let path = Bundle(for: ReportProblemViewController.self).path(forResource: "en", ofType: "lproj")!
        return Bundle(path: path)!
    }

    @Test func testStopProblemHeader() {
        // We explicitly test the English bundle to avoid host locale dependency in tests
        let bundle = englishBundle()
        let expected = bundle.localizedString(
            forKey: "report_problem_controller.stop_problem.header",
            value: "MISSING",
            table: nil
        )
        #expect(expected == "Problem with the Stop")
    }

    @Test func testVehicleProblemHeader() {
        let bundle = englishBundle()
        let expected = bundle.localizedString(
            forKey: "report_problem_controller.trip_problem.header",
            value: "MISSING",
            table: nil
        )
        #expect(expected == "Problem with a Trip")
    }
}
