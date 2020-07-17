//
//  FormattersTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import XCTest
@testable import OBAKit
@testable import OBAKitCore
import Nimble

// swiftlint:disable force_try

enum ModelDecodingError: Error {
    case invalidData
    case invalidReferences
    case invalidModelList
}

class FormattersTests: OBATestCase {
    let usLocale = Locale(identifier: "en_US")
    let calendar = Calendar(identifier: .gregorian)

    func testExample() {
        let formatters = Formatters(locale: usLocale, calendar: calendar, themeColors: ThemeColors())
        let stopArrivals = try! Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: "arrivals-and-departures-for-stop-1_75414.json")
        let arrDep = stopArrivals.arrivalsAndDepartures.first!

        let str = formatters.explanation(from: arrDep)

        expect(str).to(match("Arrived \\d+ min ago"))
    }
}
