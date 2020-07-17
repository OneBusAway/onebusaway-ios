//
//  NetworkHelperTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import XCTest
import Nimble

@testable import OBAKit
@testable import OBAKitCore

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
