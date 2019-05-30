//
//  NetworkHelperTests.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 2/7/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import Foundation
import XCTest
import Nimble

@testable import OBAKit

class NetworkHelperTests: OBATestCase {
    func testDictionaryToQueryItems_success() {
        let dict: [String: Any] = ["one": 2, "three": "four"]
        let queryItems = NetworkHelpers.dictionary(toQueryItems: dict).sorted(by: { $0.name < $1.name })

        let qi1 = queryItems.first!
        let qi2 = queryItems.last!

        expect(qi1.name) == "one"
        expect(qi1.value) == "2"

        expect(qi2.name) == "three"
        expect(qi2.value) == "four"
    }

    func testEscapePathVariable() {
        let pathVar = "Here is a ridiculous string!/But not impossible to see in OBA's data :-\\"
        let escaped = NetworkHelpers.escapePathVariable(pathVar)

        expect(escaped) == "Here%20is%20a%20ridiculous%20string!%2FBut%20not%20impossible%20to%20see%20in%20OBA's%20data%20:-%5C"
    }

    func testDictionaryToHTTPBodyData() {
        let dict: [String: Any] = ["one": 2, "three": "four"]
        let data = NetworkHelpers.dictionary(toHTTPBodyData: dict)

        let expectedData1 = "one=2&three=four".data(using: .utf8)
        let match1 = (expectedData1 == data)

        let expectedData2 = "three=four&one=2".data(using: .utf8)
        let match2 = (expectedData2 == data)

        expect(match1 || match2).to(beTrue())
    }
}
