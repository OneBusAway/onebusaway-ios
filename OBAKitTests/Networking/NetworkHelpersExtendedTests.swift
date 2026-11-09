//
//  NetworkHelpersExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

/// Tests for `NetworkHelpers.escapePathVariable`, `dictionary(toQueryItems:)`,
/// and `dictionary(toHTTPBodyData:)` with RFC 3986 unreserved character preservation
/// and special transit data characters (&, +, =, /, spaces, semicolons).
@Suite(.serialized)
struct NetworkHelpersExtendedTests {

    // MARK: - escapePathVariable

    @Test func `escapePathVariable replaces slashes and spaces`() {
        let complexPath = "1_10020/sub-stop/A & B"
        let escaped = NetworkHelpers.escapePathVariable(complexPath)

        #expect(!escaped.contains("/"))
        #expect(escaped.contains("%2F"))
        #expect(escaped.contains("%20"))
    }

    @Test func `escapePathVariable leaves clean alphanumeric path unchanged`() {
        let clean = "standard_stop_123"
        #expect(NetworkHelpers.escapePathVariable(clean) == "standard_stop_123")
    }

    @Test func `escapePathVariable handles empty string gracefully`() {
        #expect(NetworkHelpers.escapePathVariable("").isEmpty)
    }

    // MARK: - dictionary(toQueryItems:)

    @Test func `dictionary toQueryItems converts empty dictionary to empty array`() {
        let empty: [String: Any] = [:]
        #expect(NetworkHelpers.dictionary(toQueryItems: empty).isEmpty)
    }

    @Test func `dictionary toQueryItems converts multiple scalar and boolean types`() {
        let params: [String: Any] = [
            "lat": 47.6062,
            "lon": -122.3321,
            "radius": 500,
            "includeStatus": true,
            "agency": "KCM"
        ]

        let items = NetworkHelpers.dictionary(toQueryItems: params)
        #expect(items.count == 5)

        let map = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value) })
        #expect(map["lat"] == "47.6062")
        #expect(map["lon"] == "-122.3321")
        #expect(map["radius"] == "500")
        #expect(map["includeStatus"] == "true")
        #expect(map["agency"] == "KCM")
    }

    // MARK: - dictionary(toHTTPBodyData:) RFC 3986 Compliance

    @Test func `dictionary toHTTPBodyData correctly percent-encodes ampersands and plus signs`() {
        // RFC 3986 form-unreserved: alphanumerics, -, ., _, ~
        // Characters like '&', '+', '=', ';' must be escaped so they don't break key=value parsing
        let form: [String: Any] = [
            "comment": "Waiting at 3rd Ave & Pine St + delay",
            "equation": "1+1=2;test"
        ]

        let data = NetworkHelpers.dictionary(toHTTPBodyData: form)
        let bodyString = String(data: data, encoding: .utf8)!

        // Ampersand in value MUST be escaped to %26 so it doesn't split the parameter
        #expect(bodyString.contains("3rd%20Ave%20%26%20Pine%20St%20%2B%20delay"))
        // Plus sign in equation MUST be escaped to %2B (not left raw or turned into space)
        #expect(bodyString.contains("1%2B1%3D2%3Btest"))

        // The only unescaped '&' must be the parameter delimiter between the two fields
        let pairs = bodyString.split(separator: "&")
        #expect(pairs.count == 2)
    }

    @Test func `dictionary toHTTPBodyData preserves unreserved characters without escaping`() {
        let unreserved = "alpha-NUM_123.test~val"
        let data = NetworkHelpers.dictionary(toHTTPBodyData: ["key": unreserved])
        let bodyString = String(data: data, encoding: .utf8)!

        #expect(bodyString == "key=alpha-NUM_123.test~val")
    }
}
