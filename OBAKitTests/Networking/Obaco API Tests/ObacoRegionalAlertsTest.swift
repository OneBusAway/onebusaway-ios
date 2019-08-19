//
//  ObacoRegionalAlertsTest.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 8/17/19.
//

import XCTest
import Nimble
import OHHTTPStubs
@testable import OBAKit

class ObacoRegionalAlertsTest: OBATestCase {
    func testRegionalAlertsAPIPath() {
        expect(RegionalAlertsOperation.buildObacoAPIPath(regionID: "0")) == "/api/v1/regions/0/alerts.pb"
    }

    func testSuccessfulStopsForRouteRequest() {
        let apiPath = RegionalAlertsOperation.buildObacoAPIPath(regionID: obacoRegionID)

        stub(condition: isHost(self.obacoHost) && isPath(apiPath)) { _ in
            return OHHTTPStubsResponse.dataFile(named: "puget_sound_alerts.pb")
        }

        waitUntil { done in
            let op = self.obacoService.getAlerts()
            op.completionBlock = {
                expect(op.data).toNot(beNil())
                done()
            }
        }
    }
}
