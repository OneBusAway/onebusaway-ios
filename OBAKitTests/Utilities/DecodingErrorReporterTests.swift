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

/// Tests the formatting and reporting logic of DecodingErrorReporter.
@Suite(.serialized)
final class DecodingErrorReporterTests {

    /// A mock coding key used to build context paths for decoding errors.
    struct MockKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }
    }

    /// Verifies that keyNotFound errors are formatted with the missing key and path.
    @Test func testMessageForKeyNotFound() {
        let key = MockKey(stringValue: "id")!
        let context = DecodingError.Context(codingPath: [MockKey(stringValue: "data")!], debugDescription: "No value associated with key.")
        let error = DecodingError.keyNotFound(key, context)

        let message = DecodingErrorReporter.message(from: error)
        #expect(message.contains("Missing key: 'id'"))
        #expect(message.contains("Path: data"))
        #expect(message.contains("Context: No value associated with key."))
    }

    /// Verifies that typeMismatch errors display the expected type and path.
    @Test func testMessageForTypeMismatch() {
        let context = DecodingError.Context(codingPath: [MockKey(stringValue: "data")!, MockKey(stringValue: "list")!], debugDescription: "Expected String but found Int.")
        let error = DecodingError.typeMismatch(String.self, context)

        let message = DecodingErrorReporter.message(from: error)
        #expect(message.contains("Type mismatch (expected String)"))
        #expect(message.contains("Path: data → list"))
        #expect(message.contains("Context: Expected String but found Int."))
    }

    /// Verifies that valueNotFound errors indicate a missing value of the correct type.
    @Test func testMessageForValueNotFound() {
        let context = DecodingError.Context(codingPath: [], debugDescription: "Expected String but found null.")
        let error = DecodingError.valueNotFound(String.self, context)

        let message = DecodingErrorReporter.message(from: error)
        #expect(message.contains("Missing value (expected String)"))
        #expect(message.contains("Path: root"))
        #expect(message.contains("Context: Expected String but found null."))
    }

    /// Verifies that dataCorrupted errors properly format their context messages.
    @Test func testMessageForDataCorrupted() {
        let context = DecodingError.Context(codingPath: [MockKey(stringValue: "blob")!], debugDescription: "The given data was not valid JSON.")
        let error = DecodingError.dataCorrupted(context)

        let message = DecodingErrorReporter.message(from: error)
        #expect(message.contains("Data corrupted"))
        #expect(message.contains("Path: blob"))
        #expect(message.contains("Context: The given data was not valid JSON."))
    }

    /// Tests that calling report(...) passes the correct url, method, and formatted message to the registered handler.
    @Test func testReportHandlerInvocation() {
        let context = DecodingError.Context(codingPath: [], debugDescription: "Test")
        let error = DecodingError.dataCorrupted(context)
        let url = URL(string: "https://api.onebusaway.org/test")!
        let method = "GET"

        var handlerInvoked = false
        var reportedURL: URL?
        var reportedMethod: String?

        // Save original handler
        let originalHandler = DecodingErrorReporter.reportHandler

        // Set test handler
        DecodingErrorReporter.reportHandler = { err, reqURL, reqMethod, msg in
            handlerInvoked = true
            reportedURL = reqURL
            reportedMethod = reqMethod
        }

        // Trigger report
        DecodingErrorReporter.report(error: error, url: url, httpMethod: method)

        #expect(handlerInvoked)
        #expect(reportedURL == url)
        #expect(reportedMethod == method)

        // Restore original handler
        DecodingErrorReporter.reportHandler = originalHandler
    }
}
