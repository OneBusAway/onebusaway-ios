//
//  FrequencyTests.swift
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

@Suite(.serialized)
final class FrequencyTests {

    @Test func `Decode Frequency from JSON dictionary`() throws {
        let dictionary: [String: Any] = [
            "startTime": 1289579400000,
            "endTime": 1289602799000,
            "headway": 600
        ]

        let frequency = try Fixtures.dictionaryToModel(type: Frequency.self, dictionary: dictionary)

        #expect(frequency.startTime == Date(timeIntervalSince1970: 1289579400))
        #expect(frequency.endTime == Date(timeIntervalSince1970: 1289602799))
        #expect(frequency.headway == 600.0)
    }

    @Test func `Decode Frequency from fixture`() throws {
        let data = Fixtures.loadData(file: "frequency-vehicle.json")
        let response = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<VehicleStatus>.self, from: data)

        let tripStatus = response.entry.tripStatus
        let frequency = try #require(tripStatus.frequency)

        #expect(frequency.startTime == Date(timeIntervalSince1970: 1289579400))
        #expect(frequency.endTime == Date(timeIntervalSince1970: 1289602799))
        #expect(frequency.headway == 600.0)
    }

    @Test func `Frequency equality and hashing`() throws {
        let dict1: [String: Any] = [
            "startTime": 1289579400000,
            "endTime": 1289602799000,
            "headway": 600
        ]
        let dict2: [String: Any] = [
            "startTime": 1289579400000,
            "endTime": 1289602799000,
            "headway": 600
        ]
        let dictDifferentHeadway: [String: Any] = [
            "startTime": 1289579400000,
            "endTime": 1289602799000,
            "headway": 900
        ]
        let dictDifferentStart: [String: Any] = [
            "startTime": 1289580000000,
            "endTime": 1289602799000,
            "headway": 600
        ]
        let dictDifferentEnd: [String: Any] = [
            "startTime": 1289579400000,
            "endTime": 1289605000000,
            "headway": 600
        ]

        let freq1 = try Fixtures.dictionaryToModel(type: Frequency.self, dictionary: dict1)
        let freq2 = try Fixtures.dictionaryToModel(type: Frequency.self, dictionary: dict2)
        let freqDiffHeadway = try Fixtures.dictionaryToModel(type: Frequency.self, dictionary: dictDifferentHeadway)
        let freqDiffStart = try Fixtures.dictionaryToModel(type: Frequency.self, dictionary: dictDifferentStart)
        let freqDiffEnd = try Fixtures.dictionaryToModel(type: Frequency.self, dictionary: dictDifferentEnd)

        #expect(freq1 == freq2)
        #expect(freq1.isEqual(freq2))
        #expect(freq1.hashValue == freq2.hashValue)

        #expect(freq1 != freqDiffHeadway)
        #expect(freq1 != freqDiffStart)
        #expect(freq1 != freqDiffEnd)
        #expect(!freq1.isEqual("not a frequency"))
        #expect(!freq1.isEqual(nil))
    }

    @Test func `Decode failure when required field is missing`() {
        let missingStartTime: [String: Any] = [
            "endTime": 1289602799000,
            "headway": 600
        ]
        let missingEndTime: [String: Any] = [
            "startTime": 1289579400000,
            "headway": 600
        ]
        let missingHeadway: [String: Any] = [
            "startTime": 1289579400000,
            "endTime": 1289602799000
        ]

        #expect(throws: (any Error).self) {
            try Fixtures.dictionaryToModel(type: Frequency.self, dictionary: missingStartTime)
        }
        #expect(throws: (any Error).self) {
            try Fixtures.dictionaryToModel(type: Frequency.self, dictionary: missingEndTime)
        }
        #expect(throws: (any Error).self) {
            try Fixtures.dictionaryToModel(type: Frequency.self, dictionary: missingHeadway)
        }
    }
}
