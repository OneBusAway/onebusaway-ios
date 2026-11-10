//
//  QuestionTypeExtendedTests.swift
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
final class QuestionTypeExtendedTests: OBATestCase {

    // MARK: - Discrete String Decodability

    @Test func `QuestionType decodes all standard survey raw values`() throws {
        let cases: [(String, QuestionType)] = [
            ("\"text\"", .text),
            ("\"radio\"", .radio),
            ("\"checkbox\"", .checkbox),
            ("\"label\"", .label),
            ("\"external_survey\"", .externalSurvey)
        ]

        let decoder = JSONDecoder()
        for (rawJSON, expected) in cases {
            let decoded = try decoder.decode(QuestionType.self, from: Data(rawJSON.utf8))
            #expect(decoded == expected)
            #expect(decoded.rawValue == expected.rawValue)
        }
    }

    // MARK: - Codable Round-Trip

    @Test func `QuestionType encodes and decodes symmetrically`() throws {
        let types: [QuestionType] = [.text, .radio, .checkbox, .label, .externalSurvey]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for original in types {
            let data = try encoder.encode(original)
            let roundTripped = try decoder.decode(QuestionType.self, from: data)
            #expect(roundTripped == original)
        }
    }

    // MARK: - Unrecognized Value Rejection

    @Test func `QuestionType rejects unsupported or unknown type strings`() {
        let invalidJSON = Data("\"unsupported_matrix_format\"".utf8)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(QuestionType.self, from: invalidJSON)
        }
    }
}
