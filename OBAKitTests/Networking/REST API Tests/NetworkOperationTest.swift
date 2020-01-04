//
//  NetworkOperationTest.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 12/15/19.
//

import XCTest
import Nimble
import OHHTTPStubs
@testable import OBAKit
@testable import OBAKitCore

class NetworkOperationTest: OBATestCase {

    // Validate that URLs for San Diego should work.
    func testBuildURL_pathConstruction_SDMTS() {
        let baseURL = URL(string: "http://www.example.com/api/")!
        let path = "/api/where/example.json"

        let constructedURL = NetworkOperation.buildURL(fromBaseURL: baseURL, path: path, queryItems: [])
        expect(constructedURL.absoluteString) == "http://www.example.com/api/api/where/example.json?"
    }
}
