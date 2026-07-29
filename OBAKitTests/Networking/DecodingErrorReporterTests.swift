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

    @Test func `Report handler captures URL correctly`() {
        let capturedURL = SendableBox<URL?>(nil)
        let testURL = URL(string: "https://api.onebusaway.org/api/where/stops?key=TEST")!

        DecodingErrorReporter.reportHandler = { _, url, _, _ in
            capturedURL.value = url
        }

        let error = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Test"))
        DecodingErrorReporter.report(error: error, url: testURL, httpMethod: "GET")

        #expect(capturedURL.value == testURL)
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
