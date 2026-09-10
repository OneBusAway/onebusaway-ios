//
//  DecodingErrorReporterTests.swift
//  OBAKitCoreTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

struct DummyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(stringValue: String) {
        self.stringValue = stringValue
    }
    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

@Suite(.serialized)
final class DecodingErrorReporterTests {
    
    @Test func Message formatting for keyNotFound() {
        let key = DummyCodingKey(stringValue: "missing_key")
        let context = DecodingError.Context(codingPath: [], debugDescription: "Key was not found.")
        let error = DecodingError.keyNotFound(key, context)
        
        let message = DecodingErrorReporter.message(from: error)
        #expect(message.contains("Missing key: 'missing_key'"))
        #expect(message.contains("Path: root"))
        #expect(message.contains("Context: Key was not found."))
    }
    
    @Test func Message formatting for typeMismatch() {
        let context = DecodingError.Context(codingPath: [DummyCodingKey(stringValue: "parent"), DummyCodingKey(stringValue: "child")], debugDescription: "Expected String but found Int.")
        let error = DecodingError.typeMismatch(String.self, context)
        
        let message = DecodingErrorReporter.message(from: error)
        #expect(message.contains("Type mismatch (expected String)"))
        #expect(message.contains("Path: parent → child"))
        #expect(message.contains("Context: Expected String but found Int."))
    }
    
    @Test func Message formatting for valueNotFound() {
        let context = DecodingError.Context(codingPath: [DummyCodingKey(stringValue: "value")], debugDescription: "Null encountered.")
        let error = DecodingError.valueNotFound(Int.self, context)
        
        let message = DecodingErrorReporter.message(from: error)
        #expect(message.contains("Missing value (expected Int)"))
        #expect(message.contains("Path: value"))
        #expect(message.contains("Context: Null encountered."))
    }
    
    @Test func Message formatting for dataCorrupted() {
        let context = DecodingError.Context(codingPath: [], debugDescription: "Invalid JSON.")
        let error = DecodingError.dataCorrupted(context)
        
        let message = DecodingErrorReporter.message(from: error)
        #expect(message.contains("Data corrupted"))
        #expect(message.contains("Path: root"))
        #expect(message.contains("Context: Invalid JSON."))
    }
    
    @Test func Report handler is called() {
        let url = URL(string: "https://api.onebusaway.org/test")!
        let httpMethod = "GET"
        let context = DecodingError.Context(codingPath: [], debugDescription: "Test")
        let error = DecodingError.dataCorrupted(context)
        
        var handlerCalled = false
        var reportedURL: URL?
        var reportedMethod: String?
        var reportedMessage: String?
        
        DecodingErrorReporter.reportHandler = { err, u, m, msg in
            handlerCalled = true
            reportedURL = u
            reportedMethod = m
            reportedMessage = msg
        }
        
        DecodingErrorReporter.report(error: error, url: url, httpMethod: httpMethod)
        
        #expect(handlerCalled == true)
        #expect(reportedURL == url)
        #expect(reportedMethod == "GET")
        #expect(reportedMessage?.contains("Data corrupted") == true)
        
        // Cleanup
        DecodingErrorReporter.reportHandler = nil
    }
}
