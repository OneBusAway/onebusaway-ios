//
//  AgenciesWithCoverageModelOperationTests.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 11/5/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import CoreLocation
import MapKit
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast

class AgenciesWithCoverageModelOperationTests: OBATestCase {
    func testLoading_success() {
        let dataLoader = (restService.dataLoader as! MockDataLoader)
        let data = Fixtures.loadData(file: "agencies_with_coverage.json")
        dataLoader.mock(URLString: "https://www.example.com/api/where/agencies-with-coverage.json", with: data)

        let op = restService.getAgenciesWithCoverage()

        waitUntil { (done) in
            op.complete { result in
                switch result {
                case .failure(let error):
                    print("TODO FIXME handle error! \(error)")
                case .success(let response):
                    let agencies = response.list
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
}
