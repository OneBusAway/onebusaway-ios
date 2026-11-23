//
//  DecodingErrorReporterTests.swift
//  OBAKit
//
//  Created by Divesh Patil on 29/01/26.
//
import Foundation
import Testing
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class DecodingErrorReporterTests {

    // MARK: - Test Models
    
    struct TestModel: Decodable {
        let id: Int
        let name: String
        let nested: NestedModel
    }
    
    struct NestedModel: Decodable {
        let value: String
        let count: Int
    }

    deinit {
        DecodingErrorReporter.reportHandler = nil
        DecodingErrorReporter.diagnosticHandler = nil
    }

    // MARK: - keyNotFound Tests
    
    @Test func `Key not found`() throws {
        let json = """
        {
            "id": 123,
            "nested": {
                "value": "test",
                "count": 5
            }
        }
        """.data(using: .utf8)!
        
        do {
            _ = try JSONDecoder().decode(TestModel.self, from: json)
            Issue.record("Expected decoding to fail")
        } catch let error as DecodingError {
            let message = DecodingErrorReporter.message(from: error)
            
            #expect(message.contains("Missing key: 'name'"), "Message should contain the missing key name")
            #expect(message.contains("Path:"), "Message should contain path information")
        }
    }
    
    @Test func `Key not found with nested path`() throws {
        struct Model: Decodable {
            let data: DataWrapper
        }
        struct DataWrapper: Decodable {
            let items: [Item]
        }
        struct Item: Decodable {
            let id: Int
            let required: String
        }
        
        let json = """
        {
            "data": {
                "items": [
                    {
                        "id": 1
                    }
                ]
            }
        }
        """.data(using: .utf8)!
        
        do {
            _ = try JSONDecoder().decode(Model.self, from: json)
            Issue.record("Expected decoding to fail")
        } catch let error as DecodingError {
            let message = DecodingErrorReporter.message(from: error)
            
            #expect(message.contains("Missing key: 'required'"), "Message should contain the missing key")
            #expect(message.contains("data → items → Index 0") || message.contains("data → items"), "Message should contain the full path: \(message)")
        }
    }

    // MARK: - typeMismatch Tests
    
    @Test func `Type mismatch`() throws {
        let json = """
        {
            "id": "not_a_number",
            "name": "test",
            "nested": {
                "value": "test",
                "count": 5
            }
        }
        """.data(using: .utf8)!
        
        do {
            _ = try JSONDecoder().decode(TestModel.self, from: json)
            Issue.record("Expected decoding to fail")
        } catch let error as DecodingError {
            let message = DecodingErrorReporter.message(from: error)
            
            #expect(message.contains("Type mismatch"), "Message should indicate type mismatch")
            #expect(message.contains("Int") || message.contains("expected"), "Message should mention expected type")
            #expect(message.contains("Path:"), "Message should contain path")
        }
    }
    
    @Test func `Type mismatch in nested object`() throws {
        let json = """
        {
            "id": 123,
            "name": "test",
            "nested": {
                "value": "test",
                "count": "not_a_number"
            }
        }
        """.data(using: .utf8)!
        
        do {
            _ = try JSONDecoder().decode(TestModel.self, from: json)
            Issue.record("Expected decoding to fail")
        } catch let error as DecodingError {
            let message = DecodingErrorReporter.message(from: error)
            
            #expect(message.contains("Type mismatch"), "Message should indicate type mismatch")
            #expect(message.contains("nested"), "Message should show nested path")
        }
    }

    // MARK: - valueNotFound Tests
    
    @Test func `Value not found`() throws {
        let json = """
        {
            "id": 123,
            "name": null,
            "nested": {
                "value": "test",
                "count": 5
            }
        }
        """.data(using: .utf8)!
        
        do {
            _ = try JSONDecoder().decode(TestModel.self, from: json)
            Issue.record("Expected decoding to fail")
        } catch let error as DecodingError {
            let message = DecodingErrorReporter.message(from: error)
            
            #expect(message.contains("Missing value"), "Message should indicate missing value")
            #expect(message.contains("String") || message.contains("expected"), "Message should mention expected type")
            #expect(message.contains("Path:"), "Message should contain path")
        }
    }

    // MARK: - dataCorrupted Tests
    
    @Test func `Data corrupted`() throws {
        struct DateModel: Decodable {
            let timestamp: Date
        }
        
        let json = """
        {
            "timestamp": "not-a-valid-date"
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        do {
            _ = try decoder.decode(DateModel.self, from: json)
            Issue.record("Expected decoding to fail")
        } catch let error as DecodingError {
            let message = DecodingErrorReporter.message(from: error)
            
            #expect(message.contains("Data corrupted") || message.contains("corrupted"), "Message should indicate data corruption")
            #expect(message.contains("Path:"), "Message should contain path")
        }
    }

    // MARK: - Path Formatting Tests
    
    @Test func `Root path`() throws {
        let json = "{}".data(using: .utf8)!
        
        do {
            _ = try JSONDecoder().decode(TestModel.self, from: json)
            Issue.record("Expected decoding to fail")
        } catch let error as DecodingError {
            let message = DecodingErrorReporter.message(from: error)
            
            #expect(message.contains("Path:"), "Message should contain path information")
            #expect(message.contains("Path: root"), "Empty coding path should display 'root'")
        }
    }
    
    @Test func `Nested path formatting`() throws {
        struct DeepModel: Decodable {
            let level1: Level1
        }
        struct Level1: Decodable {
            let level2: Level2
        }
        struct Level2: Decodable {
            let level3: Level3
        }
        struct Level3: Decodable {
            let value: String
        }
        
        let json = """
        {
            "level1": {
                "level2": {
                    "level3": {}
                }
            }
        }
        """.data(using: .utf8)!
        
        do {
            _ = try JSONDecoder().decode(DeepModel.self, from: json)
            Issue.record("Expected decoding to fail")
        } catch let error as DecodingError {
            let message = DecodingErrorReporter.message(from: error)
            
            #expect(message.contains("→") || message.contains("level1") && message.contains("level2") && message.contains("level3"), "Message should show nested path with arrow separator: \(message)")
        }
    }

    // MARK: - Context Information Tests
    
    @Test func `Context information`() throws {
        let json = """
        {
            "id": 123,
            "nested": {
                "value": "test",
                "count": 5
            }
        }
        """.data(using: .utf8)!
        
        do {
            _ = try JSONDecoder().decode(TestModel.self, from: json)
            Issue.record("Expected decoding to fail")
        } catch let error as DecodingError {
            let message = DecodingErrorReporter.message(from: error)
            
            #expect(message.contains("Context:"), "Message should include context section")
        }
    }
    
    // MARK: - Handler Verification Tests
    
    @Test func `Report handler captures error type`() async {
        let testCases: [(DecodingError, String)] = [
            (.keyNotFound(TestCodingKey(stringValue: "test"), .init(codingPath: [], debugDescription: "Missing")), "keyNotFound"),
            (.typeMismatch(String.self, .init(codingPath: [], debugDescription: "Wrong type")), "typeMismatch"),
            (.valueNotFound(String.self, .init(codingPath: [], debugDescription: "Null value")), "valueNotFound"),
            (.dataCorrupted(.init(codingPath: [], debugDescription: "Corrupted")), "dataCorrupted")
        ]

        for (error, expectedType) in testCases {
            let capturedError = SendableBox<DecodingError?>(nil)

            // `report` invokes the handler synchronously, so this is satisfied
            // before the closure returns. It replaces an XCTestExpectation
            // whose `waitForExpectations(timeout: 1.0)` never actually waited —
            // the confirmation states the real contract: called exactly once.
            await confirmation("Handler called for \(expectedType)") { handlerCalled in
                DecodingErrorReporter.reportHandler = { error, _, _, _ in
                    capturedError.value = error
                    handlerCalled()
                }

                let mockURL = URL(string: "https://api.onebusaway.org/test")!
                DecodingErrorReporter.report(error: error, url: mockURL, httpMethod: "GET")
            }

            #expect(capturedError.value != nil, "Should capture \(expectedType) error")
            
            switch capturedError.value {
            case .keyNotFound where expectedType == "keyNotFound":
                #expect(true)
            case .typeMismatch where expectedType == "typeMismatch":
                #expect(true)
            case .valueNotFound where expectedType == "valueNotFound":
                #expect(true)
            case .dataCorrupted where expectedType == "dataCorrupted":
                #expect(true)
            default:
                Issue.record("Error type mismatch for \(expectedType)")
            }
        }
    }
    
    @Test func `Report handler with different HTTP methods`() async {
        let capturedMethod = SendableBox<String?>(nil)

        await confirmation("POST handler called") { handlerCalled in
            DecodingErrorReporter.reportHandler = { _, _, httpMethod, _ in
                capturedMethod.value = httpMethod
                handlerCalled()
            }

            let mockURL = URL(string: "https://api.onebusaway.org/stops")!
            let mockError = DecodingError.keyNotFound(
                TestCodingKey(stringValue: "id"),
                .init(codingPath: [], debugDescription: "Missing id")
            )

            DecodingErrorReporter.report(error: mockError, url: mockURL, httpMethod: "POST")
        }

        #expect(capturedMethod.value == "POST", "Should capture POST method correctly")
    }
    
    @Test func `Report handler not called when nil`() {
        DecodingErrorReporter.reportHandler = nil
        
        let mockURL = URL(string: "https://api.onebusaway.org/test")!
        let mockError = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Test"))
        
        DecodingErrorReporter.report(error: mockError, url: mockURL, httpMethod: "GET")
        
        #expect(true, "Should handle nil handler gracefully")
    }

    @Test func `Report handler captures URL without its query`() {
        let capturedURL = SendableBox<URL?>(nil)
        let testURL = URL(string: "https://api.onebusaway.org/api/where/stops?key=TEST")!

        DecodingErrorReporter.reportHandler = { _, url, _, _ in
            capturedURL.value = url
        }

        let error = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Test"))
        DecodingErrorReporter.report(error: error, url: testURL, httpMethod: "GET")

        #expect(capturedURL.value?.absoluteString == "https://api.onebusaway.org/api/where/stops")
    }

    @Test func `Report handler captures message correctly`() {
        let capturedMessage = SendableBox<String?>(nil)
        let testURL = URL(string: "https://api.onebusaway.org/api/where/stops?key=TEST")!

        DecodingErrorReporter.reportHandler = { _, _, _, message in
            capturedMessage.value = message
        }

        let error = DecodingError.keyNotFound(
            TestCodingKey(stringValue: "fare"),
            .init(codingPath: [], debugDescription: "Missing fare key")
        )
        DecodingErrorReporter.report(error: error, url: testURL, httpMethod: "GET")

        #expect(capturedMessage.value != nil)
        #expect(capturedMessage.value!.contains("Missing key: 'fare'"))
    }
    
    // MARK: - DecodingErrorDiagnostic Tests

    @Test func `Diagnostic generation for keyNotFound`() throws {
        let json = """
        {
            "id": 123,
            "nested": {
                "value": "test",
                "count": 5
            }
        }
        """.data(using: .utf8)!

        do {
            _ = try JSONDecoder().decode(TestModel.self, from: json)
            Issue.record("Expected decoding to fail")
        } catch let error as DecodingError {
            let fixedDate = Date(timeIntervalSince1970: 1700000000)
            let testURL = URL(string: "https://api.onebusaway.org/api/where/stops?key=SECRET_TOKEN&lat=47.6097&lon=-122.3331")!
            let diagnostic = DecodingErrorReporter.diagnostic(for: error, url: testURL, httpMethod: "GET", date: fixedDate)

            #expect(diagnostic.errorType == "keyNotFound")
            #expect(diagnostic.missingKey == "name")
            #expect(diagnostic.expectedType == nil)
            #expect(diagnostic.codingPath.isEmpty)
            #expect(diagnostic.schemaPath == "root")
            #expect(diagnostic.httpMethod == "GET")
            #expect(diagnostic.timestamp == fixedDate)
            #expect(diagnostic.message.contains("Missing key: 'name'"))
            #expect(!diagnostic.debugDescription.isEmpty)
            #expect(!diagnostic.url.absoluteString.contains("SECRET_TOKEN"))
            #expect(!diagnostic.url.absoluteString.contains("47.6097"))
            let query = diagnostic.url.query?.removingPercentEncoding ?? (diagnostic.url.query ?? "")
            #expect(query.contains("key=[REDACTED]"))
            #expect(query.contains("lat=[REDACTED]"))
            #expect(query.contains("lon=[REDACTED]"))
        }
    }

    @Test func `Diagnostic generation for keyNotFound with nested path`() throws {
        struct Model: Decodable {
            let data: DataWrapper
        }
        struct DataWrapper: Decodable {
            let items: [Item]
        }
        struct Item: Decodable {
            let id: Int
            let required: String
        }

        let json = """
        {
            "data": {
                "items": [
                    {
                        "id": 1
                    }
                ]
            }
        }
        """.data(using: .utf8)!

        do {
            _ = try JSONDecoder().decode(Model.self, from: json)
            Issue.record("Expected decoding to fail")
        } catch let error as DecodingError {
            let mockURL = URL(string: "https://api.onebusaway.org/nested")!
            let diagnostic = DecodingErrorReporter.diagnostic(for: error, url: mockURL, httpMethod: "POST")

            #expect(diagnostic.errorType == "keyNotFound")
            #expect(diagnostic.missingKey == "required")
            #expect(diagnostic.expectedType == nil)
            #expect(diagnostic.codingPath.contains("data"))
            #expect(diagnostic.codingPath.contains("items"))
            #expect(diagnostic.schemaPath.contains("data → items"))
            #expect(diagnostic.httpMethod == "POST")
        }
    }

    @Test func `Diagnostic generation for typeMismatch`() throws {
        let json = """
        {
            "id": "not_a_number",
            "name": "test",
            "nested": {
                "value": "test",
                "count": 5
            }
        }
        """.data(using: .utf8)!

        do {
            _ = try JSONDecoder().decode(TestModel.self, from: json)
            Issue.record("Expected decoding to fail")
        } catch let error as DecodingError {
            let mockURL = URL(string: "https://api.onebusaway.org/type")!
            let diagnostic = DecodingErrorReporter.diagnostic(for: error, url: mockURL, httpMethod: "GET")

            #expect(diagnostic.errorType == "typeMismatch")
            #expect(diagnostic.missingKey == nil)
            #expect(diagnostic.expectedType?.contains("Int") == true)
            #expect(diagnostic.schemaPath == "id")
            #expect(diagnostic.codingPath == ["id"])
            #expect(diagnostic.message.contains("Type mismatch"))
        }
    }

    @Test func `Diagnostic generation for valueNotFound`() throws {
        let json = """
        {
            "id": 123,
            "name": null,
            "nested": {
                "value": "test",
                "count": 5
            }
        }
        """.data(using: .utf8)!

        do {
            _ = try JSONDecoder().decode(TestModel.self, from: json)
            Issue.record("Expected decoding to fail")
        } catch let error as DecodingError {
            let mockURL = URL(string: "https://api.onebusaway.org/value")!
            let diagnostic = DecodingErrorReporter.diagnostic(for: error, url: mockURL, httpMethod: "GET")

            #expect(diagnostic.errorType == "valueNotFound")
            #expect(diagnostic.missingKey == nil)
            #expect(diagnostic.expectedType?.contains("String") == true)
            #expect(diagnostic.schemaPath == "name")
            #expect(diagnostic.codingPath == ["name"])
            #expect(diagnostic.message.contains("Missing value"))
        }
    }

    @Test func `Diagnostic generation for dataCorrupted`() throws {
        struct DateModel: Decodable {
            let timestamp: Date
        }

        let json = """
        {
            "timestamp": "not-a-valid-date"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            _ = try decoder.decode(DateModel.self, from: json)
            Issue.record("Expected decoding to fail")
        } catch let error as DecodingError {
            let mockURL = URL(string: "https://api.onebusaway.org/corrupted")!
            let diagnostic = DecodingErrorReporter.diagnostic(for: error, url: mockURL, httpMethod: "PUT")

            #expect(diagnostic.errorType == "dataCorrupted")
            #expect(diagnostic.missingKey == nil)
            #expect(diagnostic.expectedType == nil)
            #expect(diagnostic.schemaPath == "root")
            #expect(diagnostic.codingPath.isEmpty)
            #expect(diagnostic.httpMethod == "PUT")
            #expect(diagnostic.message.contains("Data corrupted"))
        }
    }

    // MARK: - Query Redaction Tests

    @Test func `Query redaction sanitizes tokens and user coordinates`() {
        let sensitiveURL = URL(string: "https://api.onebusaway.org/api/where/stops-for-location.json?key=SECRET_TOKEN&token=XYZ&lat=47.6097&lon=-122.3331&latitude=47.6097&longitude=-122.3331")!
        let redactedURL = DecodingErrorReporter.redactURL(sensitiveURL)

        #expect(!redactedURL.absoluteString.contains("SECRET_TOKEN"))
        #expect(!redactedURL.absoluteString.contains("XYZ"))
        #expect(!redactedURL.absoluteString.contains("47.6097"))
        #expect(!redactedURL.absoluteString.contains("-122.3331"))

        let query = redactedURL.query?.removingPercentEncoding ?? (redactedURL.query ?? "")
        #expect(query.contains("key=[REDACTED]"))
        #expect(query.contains("token=[REDACTED]"))
        #expect(query.contains("lat=[REDACTED]"))
        #expect(query.contains("lon=[REDACTED]"))
        #expect(query.contains("latitude=[REDACTED]"))
        #expect(query.contains("longitude=[REDACTED]"))

        let components = URLComponents(url: redactedURL, resolvingAgainstBaseURL: false)
        #expect(components?.queryItems?.first(where: { $0.name == "key" })?.value == "[REDACTED]")
        #expect(components?.queryItems?.first(where: { $0.name == "token" })?.value == "[REDACTED]")
        #expect(components?.queryItems?.first(where: { $0.name == "lat" })?.value == "[REDACTED]")
        #expect(components?.queryItems?.first(where: { $0.name == "lon" })?.value == "[REDACTED]")
        #expect(components?.queryItems?.first(where: { $0.name == "latitude" })?.value == "[REDACTED]")
        #expect(components?.queryItems?.first(where: { $0.name == "longitude" })?.value == "[REDACTED]")
    }

    @Test func `Query redaction preserves URLs without query parameters`() {
        let cleanURL = URL(string: "https://api.onebusaway.org/api/where/stops")!
        let redacted = DecodingErrorReporter.redactURL(cleanURL)
        #expect(redacted == cleanURL)
    }

    @Test func `Query redaction clears URL fragment`() {
        let urlWithFragment = URL(string: "https://api.onebusaway.org/api/where/stops?key=TEST&lat=47.6#sensitive_anchor")!
        let redacted = DecodingErrorReporter.redactURL(urlWithFragment)
        #expect(redacted.fragment == nil)
        #expect(!redacted.absoluteString.contains("sensitive_anchor"))
        #expect(redacted.absoluteString == "https://api.onebusaway.org/api/where/stops?key=%5BREDACTED%5D&lat=%5BREDACTED%5D")

        let noQueryWithFragment = URL(string: "https://api.onebusaway.org/api/where/stops#fragment_only")!
        let redactedNoQuery = DecodingErrorReporter.redactURL(noQueryWithFragment)
        #expect(redactedNoQuery.fragment == nil)
        #expect(!redactedNoQuery.absoluteString.contains("fragment_only"))
        #expect(redactedNoQuery.absoluteString == "https://api.onebusaway.org/api/where/stops")
    }

    // MARK: - Codable Serialization Tests

    @Test func `DecodingErrorDiagnostic JSON serialization round trip`() throws {
        let fixedDate = Date(timeIntervalSince1970: 1700000000)
        let original = DecodingErrorDiagnostic(
            errorType: "keyNotFound",
            schemaPath: "data → items → 0 → id",
            codingPath: ["data", "items", "0", "id"],
            missingKey: "id",
            expectedType: nil,
            debugDescription: "No value associated with key 'id'",
            message: "Missing key: 'id'\nPath: data → items → 0 → id",
            url: URL(string: "https://api.onebusaway.org/api/where/stops?key=%5BREDACTED%5D")!,
            httpMethod: "POST",
            timestamp: fixedDate
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DecodingErrorDiagnostic.self, from: data)

        #expect(decoded == original)
        #expect(decoded.errorType == "keyNotFound")
        #expect(decoded.schemaPath == "data → items → 0 → id")
        #expect(decoded.codingPath == ["data", "items", "0", "id"])
        #expect(decoded.missingKey == "id")
        #expect(decoded.expectedType == nil)
        #expect(decoded.debugDescription == "No value associated with key 'id'")
        #expect(decoded.message == original.message)
        #expect(decoded.url == original.url)
        #expect(decoded.httpMethod == "POST")
        #expect(decoded.timestamp == fixedDate)
    }

    // MARK: - Diagnostic Handler Tests

    @Test func `Report invokes diagnosticHandler when configured`() async {
        let capturedDiagnostic = SendableBox<DecodingErrorDiagnostic?>(nil)
        let testURL = URL(string: "https://api.onebusaway.org/api/where/stops?key=SECRET_TOKEN&lat=47.6097&lon=-122.3331")!

        await confirmation("Diagnostic handler called") { handlerCalled in
            DecodingErrorReporter.diagnosticHandler = { diagnostic in
                capturedDiagnostic.value = diagnostic
                handlerCalled()
            }

            let error = DecodingError.keyNotFound(
                TestCodingKey(stringValue: "id"),
                .init(codingPath: [], debugDescription: "Missing id")
            )

            DecodingErrorReporter.report(error: error, url: testURL, httpMethod: "GET")
        }

        #expect(capturedDiagnostic.value != nil)
        #expect(capturedDiagnostic.value?.errorType == "keyNotFound")
        #expect(capturedDiagnostic.value?.missingKey == "id")
        #expect(capturedDiagnostic.value?.httpMethod == "GET")
        #expect(capturedDiagnostic.value?.url.absoluteString.contains("SECRET_TOKEN") == false)
        #expect(capturedDiagnostic.value?.url.absoluteString.contains("47.6097") == false)
        let query = capturedDiagnostic.value?.url.query?.removingPercentEncoding ?? (capturedDiagnostic.value?.url.query ?? "")
        #expect(query.contains("key=[REDACTED]"))
        #expect(query.contains("lat=[REDACTED]"))
    }

    @Test func `Report invokes both reportHandler and diagnosticHandler when both configured`() async {
        let capturedLegacyURL = SendableBox<URL?>(nil)
        let capturedDiagnostic = SendableBox<DecodingErrorDiagnostic?>(nil)
        let testURL = URL(string: "https://api.onebusaway.org/api/where/stops?key=SECRET_TOKEN&lat=47.6097")!

        await confirmation("Both handlers called", expectedCount: 2) { handlerCalled in
            DecodingErrorReporter.reportHandler = { _, url, _, _ in
                capturedLegacyURL.value = url
                handlerCalled()
            }

            DecodingErrorReporter.diagnosticHandler = { diagnostic in
                capturedDiagnostic.value = diagnostic
                handlerCalled()
            }

            let error = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Corrupted data"))
            DecodingErrorReporter.report(error: error, url: testURL, httpMethod: "POST")
        }

        // Backward compatibility: legacy handler receives stripped URL without query
        #expect(capturedLegacyURL.value?.absoluteString == "https://api.onebusaway.org/api/where/stops")
        // Structured handler receives diagnostic with redacted query
        let query = capturedDiagnostic.value?.url.query?.removingPercentEncoding ?? (capturedDiagnostic.value?.url.query ?? "")
        #expect(query.contains("key=[REDACTED]"))
        #expect(capturedDiagnostic.value?.url.absoluteString.contains("SECRET_TOKEN") == false)
        #expect(capturedDiagnostic.value?.errorType == "dataCorrupted")
        #expect(capturedDiagnostic.value?.httpMethod == "POST")
    }

    // MARK: - Helper Types

    struct TestCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        
        init(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }
        
        init?(intValue: Int) {
            self.stringValue = "\(intValue)"
            self.intValue = intValue
        }
    }
}
