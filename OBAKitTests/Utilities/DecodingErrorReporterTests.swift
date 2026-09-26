//
//  DecodingErrorReporterTests.swift
//  OBAKitTests
//
//  Copyright Â© Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

@Suite(.serialized)
final class DecodingErrorReporterTests {

    private struct TestKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    @Test func testMessageForKeyNotFound() {
        let key = TestKey(stringValue: "id")!
        let context = DecodingError.Context(codingPath: [TestKey(stringValue: "data")!], debugDescription: "Key is missing")
        let error = DecodingError.keyNotFound(key, context)
        
        let message = DecodingErrorReporter.message(from: error)
        #expect(message.contains("Missing key: 'id'"))
        #expect(message.contains("Path: data"))
        #expect(message.contains("Context: Key is missing"))
    }

    @Test func testMessageForTypeMismatch() {
        let context = DecodingError.Context(codingPath: [TestKey(stringValue: "user")!, TestKey(stringValue: "age")!], debugDescription: "Expected Int but found String")
        let error = DecodingError.typeMismatch(Int.self, context)
        
        let message = DecodingErrorReporter.message(from: error)
        #expect(message.contains("Type mismatch (expected Int)"))
        #expect(message.contains("Path: user â†’ age"))
        #expect(message.contains("Context: Expected Int but found String"))
    }

    @Test func testMessageForValueNotFound() {
        let context = DecodingError.Context(codingPath: [], debugDescription: "Null encountered")
        let error = DecodingError.valueNotFound(String.self, context)
        
        let message = DecodingErrorReporter.message(from: error)
        #expect(message.contains("Missing value (expected String)"))
        #expect(message.contains("Path: root"))
        #expect(message.contains("Context: Null encountered"))
    }

    @Test func testMessageForDataCorrupted() {
        let context = DecodingError.Context(codingPath: [TestKey(stringValue: "payload")!], debugDescription: "Invalid format")
        let error = DecodingError.dataCorrupted(context)
        
        let message = DecodingErrorReporter.message(from: error)
        #expect(message.contains("Data corrupted"))
        #expect(message.contains("Path: payload"))
        #expect(message.contains("Context: Invalid format"))
    }

    @Test func testReportHandlerInvocation() {
        var reportedError: DecodingError?
        var reportedURL: URL?
        var reportedMethod: String?
        var reportedMessage: String?
        
        DecodingErrorReporter.reportHandler = { error, url, httpMethod, message in
            reportedError = error
            reportedURL = url
            reportedMethod = httpMethod
            reportedMessage = message
        }
        
        let context = DecodingError.Context(codingPath: [], debugDescription: "Error")
        let error = DecodingError.dataCorrupted(context)
        let testURL = URL(string: "https://api.onebusaway.org/test")!
        
        DecodingErrorReporter.report(error: error, url: testURL, httpMethod: "GET")
        
        #expect(reportedURL == testURL)
        #expect(reportedMethod == "GET")
        #expect(reportedMessage != nil)
        #expect(reportedMessage?.contains("Data corrupted") == true)
        
        // Reset the handler
        DecodingErrorReporter.reportHandler = nil
    }
}
