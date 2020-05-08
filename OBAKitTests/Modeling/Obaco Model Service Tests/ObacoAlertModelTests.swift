//
//  ObacoAlertModelTests.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 8/17/19.
//

import XCTest
import Nimble
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try force_cast

class ObacoAlertModelTests: OBATestCase {
    func testSuccesfulModelRequest() {
        let dataLoader = (obacoService.dataLoader as! MockDataLoader)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        let locale = Locale.current

        let agencies = try! Fixtures.loadRESTAPIPayload(type: [AgencyWithCoverage].self, fileName: "agencies_with_coverage.json")
        expect(agencies.count) == 11

        let op = obacoService.getAlerts(agencies: agencies)

        waitUntil { done in
            op.complete { alerts in
                expect(alerts.count) == 20
                let first = alerts.first!
                expect(first.startDate) == Date.fromComponents(year: 2018, month: 10, day: 09, hour: 15, minute: 01, second: 00)
                expect(first.endDate) == Date.fromComponents(year: 2018, month: 10, day: 09, hour: 23, minute: 01, second: 00)

                expect(first.URLForLocale(locale)!.absoluteString) == "https://m.soundtransit.org/node/19133"
                expect(first.titleForLocale(locale)!) == "Sounder Lakewood-Seattle - Delay - #1514 (7:20 am TAC dep)  20 minutes at Auburn Station due to a medical emergency"
                expect(first.bodyForLocale(locale)!.starts(with: "Sounder south line train #1514 (7:20 a.m. Tacoma departure)")).to(beTrue())
                done()
            }
        }
    }
}
