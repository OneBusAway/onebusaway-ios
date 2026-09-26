//
//  DecodingErrorReporterTests.swift
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
        #expect(message.contains("Path: user → age"))
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

    private final class ReportedData: @unchecked Sendable {
        var error: DecodingError?
        var url: URL?
        var method: String?
        var message: String?
        let lock = NSLock()
    }

    @Test func testReportHandlerInvocation() {
        let reportedData = ReportedData()
        
        DecodingErrorReporter.reportHandler = { error, url, httpMethod, message in
            reportedData.lock.lock()
            reportedData.error = error
            reportedData.url = url
            reportedData.method = httpMethod
            reportedData.message = message
            reportedData.lock.unlock()
        }
        
        let context = DecodingError.Context(codingPath: [], debugDescription: "Error")
        let originalError = DecodingError.dataCorrupted(context)
        let testURL = URL(string: "https://api.onebusaway.org/test")!
        
        DecodingErrorReporter.report(error: originalError, url: testURL, httpMethod: "GET")
        
        reportedData.lock.lock()
        let finalError = reportedData.error
        let finalURL = reportedData.url
        let finalMethod = reportedData.method
        let finalMessage = reportedData.message
        reportedData.lock.unlock()
        
        #expect(finalURL == testURL)
        #expect(finalMethod == "GET")
        #expect(finalMessage != nil)
        #expect(finalMessage?.contains("Data corrupted") == true)
        
        if case .dataCorrupted(let reportedContext) = finalError,
           case .dataCorrupted(let originalContext) = originalError {
            #expect(reportedContext.debugDescription == originalContext.debugDescription)
        } else {
            Issue.record("Expected dataCorrupted error to be forwarded to the handler")
        }
        
        // Reset the handler
        DecodingErrorReporter.reportHandler = nil
    }
}
