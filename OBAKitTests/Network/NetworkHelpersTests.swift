//
//  NetworkHelpersTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

@Suite(.serialized)
final class NetworkHelpersTests {
    @Test func testDictionaryToQueryItems() {
        let dict: [String: Any] = [
            "key1": "value1",
            "key2": 42
        ]
        
        let queryItems = NetworkHelpers.dictionary(toQueryItems: dict)
        
        #expect(queryItems.count == 2)
        #expect(queryItems.contains(where: { $0.name == "key1" && $0.value == "value1" }))
        #expect(queryItems.contains(where: { $0.name == "key2" && $0.value == "42" }))
    }

    @Test func testEscapePathVariable() {
        let path = "1_10020/test"
        let escaped = NetworkHelpers.escapePathVariable(path)
        #expect(escaped == "1_10020%2Ftest")
        
        let spaces = "test path"
        let escapedSpaces = NetworkHelpers.escapePathVariable(spaces)
        #expect(escapedSpaces == "test%20path")
    }

    @Test func testDictionaryToHTTPBodyData() {
        let dict: [String: Any] = [
            "q": "15th Ave & Broadway",
            "val": "a+b=c"
        ]
        
        let data = NetworkHelpers.dictionary(toHTTPBodyData: dict)
        let dataString = String(data: data, encoding: .utf8) ?? ""
        
        // Both elements should be properly escaped and joined by &
        #expect(dataString.contains("q=15th%20Ave%20%26%20Broadway"))
        #expect(dataString.contains("val=a%2Bb%3Dc"))
        #expect(dataString.contains("&"))
    }
}
