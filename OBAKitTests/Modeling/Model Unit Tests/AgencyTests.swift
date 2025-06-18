//
//  AgencyTests.swift
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

class AgencyTests: OBATestCase {
    
    func test_decodeValidAgency() {
        let agencyData: [String: Any] = [
            "id": "1",
            "name": "King County Metro",
            "url": "https://kingcounty.gov/metro",
            "timezone": "America/Los_Angeles",
            "lang": "en",
            "phone": "206-553-3000",
            "fareUrl": "https://kingcounty.gov/metro/fares",
            "email": "customer.service@kingcounty.gov",
            "disclaimer": "This is test data",
            "privateService": false
        ]
        
        let agency = try! Fixtures.dictionaryToModel(type: Agency.self, dictionary: agencyData)
        
        expect(agency.id) == "1"
        expect(agency.name) == "King County Metro"
        expect(agency.agencyURL.absoluteString) == "https://kingcounty.gov/metro"
        expect(agency.timeZone) == "America/Los_Angeles"
        expect(agency.language) == "en"
        expect(agency.phone) == "206-553-3000"
        expect(agency.fareURL?.absoluteString) == "https://kingcounty.gov/metro/fares"
        expect(agency.email) == "customer.service@kingcounty.gov"
        expect(agency.disclaimer) == "This is test data"
        expect(agency.isPrivateService) == false
    }
    
    func test_decodeMinimalAgency() {
        let minimalData: [String: Any] = [
            "id": "minimal_agency",
            "name": "Minimal Agency",
            "url": "https://example.com",
            "timezone": "UTC",
            "lang": "en",
            "phone": "555-0123",
            "privateService": true
        ]
        
        let agency = try! Fixtures.dictionaryToModel(type: Agency.self, dictionary: minimalData)
        
        expect(agency.id) == "minimal_agency"
        expect(agency.name) == "Minimal Agency"
        expect(agency.agencyURL.absoluteString) == "https://example.com"
        expect(agency.timeZone) == "UTC"
        expect(agency.language) == "en"
        expect(agency.phone) == "555-0123"
        expect(agency.isPrivateService) == true
        expect(agency.fareURL).to(beNil())
        expect(agency.email).to(beNil())
        expect(agency.disclaimer).to(beNil())
    }
    
    func test_decodeWithBlankValues() {
        let dataWithBlanks: [String: Any] = [
            "id": "blank_agency",
            "name": "Agency With Blanks",
            "url": "https://example.com",
            "timezone": "UTC",
            "lang": "en",
            "phone": "555-0123",
            "privateService": false,
            "email": "",
            "disclaimer": "",
            "fareUrl": ""
        ]
        
        let agency = try! Fixtures.dictionaryToModel(type: Agency.self, dictionary: dataWithBlanks)
        
        // String.nilifyBlankValue should convert empty strings to nil, but not whitespace-only strings
        expect(agency.email).to(beNil())
        expect(agency.disclaimer).to(beNil())
        expect(agency.fareURL).to(beNil())
    }
    
    func test_encodeDecodeRoundTrip() {
        let agencyData: [String: Any] = [
            "id": "roundtrip_test",
            "name": "Test Agency",
            "url": "https://example.com",
            "timezone": "UTC",
            "lang": "en",
            "phone": "555-0123",
            "privateService": false,
            "fareUrl": "https://example.com/fares",
            "email": "test@example.com"
        ]
        
        let originalAgency = try! Fixtures.dictionaryToModel(type: Agency.self, dictionary: agencyData)
        let roundTrippedAgency = try! Fixtures.roundtripCodable(type: Agency.self, model: originalAgency)
        
        expect(roundTrippedAgency.id) == originalAgency.id
        expect(roundTrippedAgency.name) == originalAgency.name
        expect(roundTrippedAgency.agencyURL) == originalAgency.agencyURL
        expect(roundTrippedAgency.timeZone) == originalAgency.timeZone
        expect(roundTrippedAgency.language) == originalAgency.language
        expect(roundTrippedAgency.phone) == originalAgency.phone
        expect(roundTrippedAgency.fareURL) == originalAgency.fareURL
        expect(roundTrippedAgency.email) == originalAgency.email
        expect(roundTrippedAgency.isPrivateService) == originalAgency.isPrivateService
    }
    
    func test_decodeFailureWhenMissingRequiredFields() {
        var incompleteData: [String: Any] = [
            "name": "Missing ID Agency",
            "url": "https://example.com",
            "timezone": "UTC",
            "lang": "en",
            "phone": "555-0123",
            "privateService": false
        ]
        
        expect {
            try Fixtures.dictionaryToModel(type: Agency.self, dictionary: incompleteData)
        }.to(throwError())
        
        incompleteData = [
            "id": "missing_name",
            "url": "https://example.com",
            "timezone": "UTC",
            "lang": "en",
            "phone": "555-0123",
            "privateService": false
        ]
        
        expect {
            try Fixtures.dictionaryToModel(type: Agency.self, dictionary: incompleteData)
        }.to(throwError())
    }
}