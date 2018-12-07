//
//  AgenciesWithCoverageModelOperationTests.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 11/5/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
import CoreLocation
import MapKit
import OBATestHelpers
@testable import OBAKit

class AgenciesWithCoverageModelOperationTests: OBATestCase {
    func stubAPICall() {
        stub(condition: isHost(self.host) && isPath(AgenciesWithCoverageOperation.apiPath)) { _ in
            return self.JSONFile(named: "agencies_with_coverage.json")
        }
    }

    func testLoading_success() {
        stubAPICall()

        waitUntil { (done) in
            let op = self.restModelService.getAgenciesWithCoverage()
            op.completionBlock = {
                let agencies = op.agenciesWithCoverage
                let childrens = agencies.first!

                expect(agencies.count) == 11

                expect(childrens.region.center.latitude).to(beCloseTo(47.6470785))
                expect(childrens.region.center.longitude).to(beCloseTo(-122.296449))

                expect(childrens.region.span.latitudeDelta).to(beCloseTo(0.06330499999999972, within: 0.1))
                expect(childrens.region.span.longitudeDelta).to(beCloseTo(0.07930600000000254, within: 0.1))

                expect(childrens.agencyID) == "98"
                expect(childrens.agency.name) == "Seattle Children's Hospital"
                expect(childrens.agency.disclaimer).to(beNil())
                expect(childrens.agency.email).to(beNil())
                expect(childrens.agency.fareURL).to(beNil())

                done()
            }
        }
    }
}
