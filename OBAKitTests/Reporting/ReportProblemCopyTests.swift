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

    private func englishBundle() -> Bundle? {
        guard let path = Bundle(for: DonationCell.self).path(forResource: "en", ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    @Test func `Stop problem header exists in the English catalog`() throws {
        let bundle = try #require(englishBundle())
        let value = bundle.localizedString(forKey: "report_problem_controller.stop_problem.header", value: "MISSING", table: nil)
        #expect(value == "Problem with the Stop")
    }

    @Test func `Vehicle problem header exists in the English catalog`() throws {
        let bundle = try #require(englishBundle())
        let value = bundle.localizedString(forKey: "report_problem_controller.trip_problem.header", value: "MISSING", table: nil)
        #expect(value == "Problem with a Trip")
    }
}
