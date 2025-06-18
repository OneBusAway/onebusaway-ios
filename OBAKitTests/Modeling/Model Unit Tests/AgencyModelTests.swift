//
//  AgencyModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try

class AgencyModelTests: OBATestCase {

    func test_BasicAgencyDecoding() {
        let agencyData: [String: Any] = [
            "id": "1",
            "name": "King County Metro",
            "url": "https://kingcounty.gov/metro",
            "timezone": "America/Los_Angeles",
            "lang": "en",
            "phone": "206-553-3000",
            "privateService": false
        ]
        
        let agency = try! Fixtures.dictionaryToModel(type: Agency.self, dictionary: agencyData)
        
        expect(agency.id) == "1"
        expect(agency.name) == "King County Metro"
        expect(agency.agencyURL.absoluteString) == "https://kingcounty.gov/metro"
        expect(agency.timeZone) == "America/Los_Angeles"
        expect(agency.language) == "en"
        expect(agency.phone) == "206-553-3000"
        expect(agency.isPrivateService) == false
    }
}