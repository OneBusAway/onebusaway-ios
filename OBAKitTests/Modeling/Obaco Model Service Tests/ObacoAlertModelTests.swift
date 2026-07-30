//
//  ObacoAlertModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try force_cast

@Suite(.serialized)
final class ObacoAlertModelTests: OBATestCase {
    @Test func `Succesful model request`() async throws {
        let dataLoader = (obacoService.dataLoader as! MockDataLoader)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        let locale = Locale.current

        let agencies = try Fixtures.loadRESTAPIPayload(type: [AgencyWithCoverage].self, fileName: "agencies_with_coverage.json")
        #expect(agencies.count == 11, "Expected agencies_with_coverage.json fixture to contain 11 agencies")

        let alerts = try await obacoService.getAlerts(agencies: agencies)

        #expect(alerts.count == 20)

        let alert = try #require(alerts.first)
        #expect(alert.startDate == Date.fromComponents(year: 2018, month: 10, day: 09, hour: 15, minute: 01, second: 00))
        #expect(alert.endDate == Date.fromComponents(year: 2018, month: 10, day: 09, hour: 23, minute: 01, second: 00))
        #expect(alert.url(forLocale: locale)?.absoluteString == "https://m.soundtransit.org/node/19133")
        #expect(alert.title(forLocale: locale) == "Sounder Lakewood-Seattle - Delay - #1514 (7:20 am TAC dep)  20 minutes at Auburn Station due to a medical emergency")

        let body = try #require(alert.body(forLocale: locale))
        #expect(body.starts(with: "Sounder south line train #1514 (7:20 a.m. Tacoma departure)"))
    }
}
