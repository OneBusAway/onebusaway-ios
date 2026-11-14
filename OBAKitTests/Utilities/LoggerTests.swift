//
//  LoggerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class LoggerTests {
    
    @Test func `Logger correctly writes and retrieves logs`() async throws {
        // Given
        let testMessage = "Test log message \(UUID().uuidString)"
        let startDate = Date()
        
        // When
        Logger.info(testMessage)
        
        // Then: Poll OSLogStore since it writes asynchronously
        var logsFound = false
        for _ in 0..<20 {
            // Using getLogEntries with since: startDate is significantly faster 
            // than scanning all logs since boot inside combinedLogContent()
            let entries = try? Logger.getLogEntries(since: startDate)
            if let entries = entries, entries.contains(where: { $0.composedMessage.contains(testMessage) }) {
                logsFound = true
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        #expect(logsFound == true, "Log message was not found in OSLogStore after polling")
    }

    // MARK: - URL query redaction (#1732)

    private static let url = URL(string: "https://api.example.com/api/where/stops-for-location.json?key=SECRETKEY&lat=47.6&lon=-122.3")!
    private static let bareURL = "https://api.example.com/api/where/stops-for-location.json"

    @Test func `A URLError description loses the query from both failing URL keys`() {
        let error = URLError(.timedOut, userInfo: [
            NSURLErrorFailingURLErrorKey: Self.url,
            NSURLErrorFailingURLStringErrorKey: Self.url.absoluteString
        ])

        let redacted = Logger.redactingURLQueries(in: "API stop request failed: \(error)")

        #expect(!redacted.contains("SECRETKEY"))
        #expect(!redacted.contains("47.6"))
        #expect(redacted.contains("NSErrorFailingURLKey=\(Self.bareURL)"))
        #expect(redacted.contains("NSErrorFailingURLStringKey=\(Self.bareURL)"))
        #expect(redacted.contains("Code=-1001"))
    }

    @Test func `An APIError carrying an HTTPURLResponse loses the query and keeps the status code`() throws {
        let response = try #require(HTTPURLResponse(url: Self.url, statusCode: 500, httpVersion: nil, headerFields: nil))

        let redacted = Logger.redactingURLQueries(in: "getAlerts() failed: \(APIError.requestFailure(response))")

        #expect(!redacted.contains("SECRETKEY"))
        #expect(redacted.contains("URL: \(Self.bareURL) }"))
        #expect(redacted.contains("Status Code: 500"))
    }

    @Test func `Messages without a URL query are left alone`() {
        let messages = [
            "Plain message",
            "Is this a question?",
            "Loaded \(Self.bareURL)",
            "Map item at https://example.com/path#fragment"
        ]
        for message in messages {
            #expect(Logger.redactingURLQueries(in: message) == message)
        }
    }

    @Test func `Every URL in a message loses its query and the text around it stays`() {
        let message = "Retry https://a.example.com/x?key=1, then \"https://b.example.com/y?lat=2&lon=3\"."

        #expect(Logger.redactingURLQueries(in: message) == "Retry https://a.example.com/x, then \"https://b.example.com/y\".")
    }

    /// `.urlQueryAllowed` leaves `'`, `(` and `)` raw, so a search for
    /// "Lincoln's" must not end the redaction before `key`.
    @Test func `Apostrophes and parentheses in a query don't end the redaction`() {
        let messages = [
            "Failed: https://api.example.com/search/stop.json?query=Lincoln's&key=KEY&app_uid=UID",
            "Failed: https://api.example.com/search/stop.json?query=Route%20(A)&key=KEY&app_uid=UID",
            "Failed: https://api.example.com/x(v1)?key=KEY&app_uid=UID"
        ]
        for message in messages {
            let redacted = Logger.redactingURLQueries(in: message)
            #expect(!redacted.contains("KEY"), "\(message)")
            #expect(!redacted.contains("UID"), "\(message)")
        }
    }

    @Test func `A URL query ending a userInfo dictionary keeps the closing brace`() {
        let message = "UserInfo={NSErrorFailingURLStringKey=https://api.example.com/x.json?key=KEY}"

        #expect(Logger.redactingURLQueries(in: message) == "UserInfo={NSErrorFailingURLStringKey=https://api.example.com/x.json}")
    }

    @Test func `Logged messages reach the log store without the query`() async throws {
        let marker = UUID().uuidString
        let startDate = Date()

        Logger.error("Redaction \(marker): \(URLError(.notConnectedToInternet, userInfo: [NSURLErrorFailingURLErrorKey: Self.url]))")

        var message: String?
        for _ in 0..<20 {
            message = try? Logger.getLogEntries(since: startDate)
                .first(where: { $0.composedMessage.contains(marker) })?
                .composedMessage
            if message != nil { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        let logged = try #require(message, "Log message was not found in OSLogStore after polling")
        #expect(!logged.contains("SECRETKEY"))
        #expect(logged.contains(Self.bareURL))
    }
}
