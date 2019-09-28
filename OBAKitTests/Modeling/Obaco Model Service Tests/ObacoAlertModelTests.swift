//
//  ObacoAlertModelTests.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 8/17/19.
//

import XCTest
import Nimble
import OHHTTPStubs
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try

class ObacoAlertModelTests: OBATestCase {
    func testSuccesfulModelRequest() {
        let apiPath = RegionalAlertsOperation.buildObacoAPIPath(regionID: obacoRegionID)

        stub(condition: isHost(self.obacoHost) && isPath(apiPath)) { _ in
            let foo = OHHTTPStubsResponse.JSONFile(named: "puget_sound_alerts.pb")
            return foo
        }

        let agencies = try! AgencyWithCoverage.decodeFromFile(named: "agencies_with_coverage.json", in: Bundle(for: type(of: self)))
        expect(agencies.count) == 11

        waitUntil { done in
            let op = self.obacoModelService.getAlerts(agencies: agencies)
            op.then {
                let alerts = op.agencyAlerts
                expect(alerts.count) == 20
                let first = alerts.first!
                expect(first.startDate) == Date.fromComponents(year: 2018, month: 10, day: 09, hour: 15, minute: 01, second: 00)
                expect(first.endDate) == Date.fromComponents(year: 2018, month: 10, day: 09, hour: 23, minute: 01, second: 00)
                expect(first.url(language: "en")!.absoluteString) == "https://m.soundtransit.org/node/19133"
                expect(first.title(language: "en")) == "Sounder Lakewood-Seattle - Delay - #1514 (7:20 am TAC dep)  20 minutes at Auburn Station due to a medical emergency"
                expect(first.body(language: "en")!.starts(with: "Sounder south line train #1514 (7:20 a.m. Tacoma departure)")).to(beTrue())
                done()
            }
        }
    }
}
