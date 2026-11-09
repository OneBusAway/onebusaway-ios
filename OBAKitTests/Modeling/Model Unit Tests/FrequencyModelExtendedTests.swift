//
//  FrequencyModelExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Tests for `Frequency` model JSON decoding, date bounds, equality, and hash behavior.
@Suite(.serialized)
final class FrequencyModelExtendedTests: OBATestCase {

    private func makeJSON(startTime: Int, endTime: Int, headway: Double) -> Data {
        let dict: [String: Any] = [
            "startTime": startTime,
            "endTime": endTime,
            "headway": headway
        ]
        return try! JSONSerialization.data(withJSONObject: dict)
    }

    // MARK: - Decoding

    @Test func `Frequency decodes epoch millisecond dates and headway`() throws {
        // 1541142000000 = Fri Nov 02 2018 07:00:00 GMT
        // 1541145600000 = Fri Nov 02 2018 08:00:00 GMT
        // headway = 600 seconds (10 min service)
        let data = makeJSON(startTime: 1541142000000, endTime: 1541145600000, headway: 600)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let frequency = try decoder.decode(Frequency.self, from: data)

        #expect(frequency.startTime == Date(timeIntervalSince1970: 1541142000))
        #expect(frequency.endTime == Date(timeIntervalSince1970: 1541145600))
        #expect(frequency.headway == 600.0)
    }

    // MARK: - Equality and Hash

    @Test func `Frequency equality compares startTime, endTime, and headway`() {
        let d1 = Date(timeIntervalSince1970: 1000)
        let d2 = Date(timeIntervalSince1970: 2000)
        let d3 = Date(timeIntervalSince1970: 3000)

        let f1 = try! JSONDecoder.standard.decode(Frequency.self, from: makeJSON(startTime: 1000000, endTime: 2000000, headway: 300))
        let f2 = try! JSONDecoder.standard.decode(Frequency.self, from: makeJSON(startTime: 1000000, endTime: 2000000, headway: 300))
        let fDiffHeadway = try! JSONDecoder.standard.decode(Frequency.self, from: makeJSON(startTime: 1000000, endTime: 2000000, headway: 600))
        let fDiffEndTime = try! JSONDecoder.standard.decode(Frequency.self, from: makeJSON(startTime: 1000000, endTime: 3000000, headway: 300))

        #expect(f1.isEqual(f2))
        #expect(f1.hash == f2.hash)
        #expect(!f1.isEqual(fDiffHeadway))
        #expect(!f1.isEqual(fDiffEndTime))
        #expect(!f1.isEqual("not_frequency"))
        #expect(!f1.isEqual(nil))
    }

    // MARK: - Decoding Failures

    @Test func `Frequency decoding throws on missing fields`() {
        let incomplete = "{\"startTime\": 1000000}".data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            try JSONDecoder.standard.decode(Frequency.self, from: incomplete)
        }
    }
}
private extension JSONDecoder {
    static var standard: JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .millisecondsSince1970
        return dec
    }
}
