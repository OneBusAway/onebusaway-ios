//
//  DecodingErrorReporterTests.swift
//  OBAKit
//
//  Created by Divesh Patil on 29/01/26.
//
import XCTest
@testable import OBAKitCore

final class DecodingErrorReporterTests: XCTestCase {

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

    override func tearDown() {
        DecodingErrorReporter.reportHandler = nil
        super.tearDown()
    }

    // MARK: - keyNotFound Tests
    
    func testKeyNotFound() throws {
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
            XCTFail("Expected decoding to fail")
        } catch let error as DecodingError {
            let message = DecodingErrorReporter.message(from: error)
            
            XCTAssertTrue(message.contains("Missing key: 'name'"),
                         "Message should contain the missing key name")
            XCTAssertTrue(message.contains("Path:"),
                         "Message should contain path information")
        }
    }
    
    func testKeyNotFoundWithNestedPath() throws {
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
            XCTFail("Expected decoding to fail")
        } catch let error as DecodingError {
            let message = DecodingErrorReporter.message(from: error)
            
            XCTAssertTrue(message.contains("Missing key: 'required'"),
                         "Message should contain the missing key")
            XCTAssertTrue(message.contains("data → items → Index 0") || message.contains("data → items"),
                         "Message should contain the full path: \(message)")
        }
    }

    // MARK: - typeMismatch Tests
    
    func testTypeMismatch() throws {
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
            XCTFail("Expected decoding to fail")
        } catch let error as DecodingError {
            let message = DecodingErrorReporter.message(from: error)
            
            XCTAssertTrue(message.contains("Type mismatch"),
                         "Message should indicate type mismatch")
            XCTAssertTrue(message.contains("Int") || message.contains("expected"),
                         "Message should mention expected type")
            XCTAssertTrue(message.contains("Path:"),
                         "Message should contain path")
        }
    }
    
    func testTypeMismatchInNestedObject() throws {
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
            XCTFail("Expected decoding to fail")
        } catch let error as DecodingError {
            let message = DecodingErrorReporter.message(from: error)
            
            XCTAssertTrue(message.contains("Type mismatch"),
                         "Message should indicate type mismatch")
            XCTAssertTrue(message.contains("nested"),
                         "Message should show nested path")
        }
    }

    // MARK: - valueNotFound Tests
    
    func testValueNotFound() throws {
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
            XCTFail("Expected decoding to fail")
        } catch let error as DecodingError {
            let message = DecodingErrorReporter.message(from: error)
            
            XCTAssertTrue(message.contains("Missing value"),
                         "Message should indicate missing value")
            XCTAssertTrue(message.contains("String") || message.contains("expected"),
                         "Message should mention expected type")
            XCTAssertTrue(message.contains("Path:"),
                         "Message should contain path")
        }
    }

    // MARK: - dataCorrupted Tests
    
    func testDataCorrupted() throws {
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
            XCTFail("Expected decoding to fail")
        } catch let error as DecodingError {
            let message = DecodingErrorReporter.message(from: error)
            
            XCTAssertTrue(message.contains("Data corrupted") || message.contains("corrupted"),
                         "Message should indicate data corruption")
            XCTAssertTrue(message.contains("Path:"),
                         "Message should contain path")
        }
    }

    // MARK: - Path Formatting Tests
    
    func testRootPath() throws {
        let json = "{}".data(using: .utf8)!
        
        do {
            _ = try JSONDecoder().decode(TestModel.self, from: json)
            XCTFail("Expected decoding to fail")
        } catch let error as DecodingError {
            let message = DecodingErrorReporter.message(from: error)
            
            XCTAssertTrue(message.contains("Path:"),
                         "Message should contain path information")
        }
    }
    
    func testNestedPathFormatting() throws {
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
            XCTFail("Expected decoding to fail")
        } catch let error as DecodingError {
            let message = DecodingErrorReporter.message(from: error)
            
            XCTAssertTrue(message.contains("→") || message.contains("level1") && message.contains("level2") && message.contains("level3"),
                         "Message should show nested path with arrow separator: \(message)")
        }
    }

    // MARK: - Context Information Tests
    
    func testContextInformation() throws {
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
            XCTFail("Expected decoding to fail")
        } catch let error as DecodingError {
            let message = DecodingErrorReporter.message(from: error)
            
            XCTAssertTrue(message.contains("Context:"),
                         "Message should include context section")
        }
    }
    
    // MARK: - Handler Verification Tests
    
    func testReportHandlerCapturesErrorType() {
        let testCases: [(DecodingError, String)] = [
            (.keyNotFound(TestCodingKey(stringValue: "test"), .init(codingPath: [], debugDescription: "Missing")), "keyNotFound"),
            (.typeMismatch(String.self, .init(codingPath: [], debugDescription: "Wrong type")), "typeMismatch"),
            (.valueNotFound(String.self, .init(codingPath: [], debugDescription: "Null value")), "valueNotFound"),
            (.dataCorrupted(.init(codingPath: [], debugDescription: "Corrupted")), "dataCorrupted")
        ]
        
        for (error, expectedType) in testCases {
            let expectation = self.expectation(description: "Handler called for \(expectedType)")
            let capturedError = SendableBox<DecodingError?>(nil)
            
            DecodingErrorReporter.reportHandler = { error, _, _, _ in
                capturedError.value = error
                expectation.fulfill()
            }
            
            let mockURL = URL(string: "https://api.onebusaway.org/test")!
            DecodingErrorReporter.report(error: error, url: mockURL, httpMethod: "GET")
            
            waitForExpectations(timeout: 1.0)
            XCTAssertNotNil(capturedError.value, "Should capture \(expectedType) error")
            
            switch capturedError.value {
            case .keyNotFound where expectedType == "keyNotFound":
                XCTAssertTrue(true)
            case .typeMismatch where expectedType == "typeMismatch":
                XCTAssertTrue(true)
            case .valueNotFound where expectedType == "valueNotFound":
                XCTAssertTrue(true)
            case .dataCorrupted where expectedType == "dataCorrupted":
                XCTAssertTrue(true)
            default:
                XCTFail("Error type mismatch for \(expectedType)")
            }
        }
    }
    
    func testReportHandlerWithDifferentHTTPMethods() {
        let postExpectation = self.expectation(description: "POST handler called")
        let capturedMethod = SendableBox<String?>(nil)
        
        DecodingErrorReporter.reportHandler = { _, _, httpMethod, _ in
            capturedMethod.value = httpMethod
            postExpectation.fulfill()
        }
        
        let mockURL = URL(string: "https://api.onebusaway.org/stops")!
        let mockError = DecodingError.keyNotFound(
            TestCodingKey(stringValue: "id"),
            .init(codingPath: [], debugDescription: "Missing id")
        )
        
        DecodingErrorReporter.report(error: mockError, url: mockURL, httpMethod: "POST")
        
        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(capturedMethod.value, "POST", "Should capture POST method correctly")
    }
    
    func testReportHandlerNotCalledWhenNil() {
        DecodingErrorReporter.reportHandler = nil
        
        let mockURL = URL(string: "https://api.onebusaway.org/test")!
        let mockError = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Test"))
        
        DecodingErrorReporter.report(error: mockError, url: mockURL, httpMethod: "GET")
        
        XCTAssertTrue(true, "Should handle nil handler gracefully")
    }

    func testReportHandlerCapturesURLCorrectly() {
        let capturedURL = SendableBox<URL?>(nil)
        let testURL = URL(string: "https://api.onebusaway.org/api/where/stops?key=TEST")!

        DecodingErrorReporter.reportHandler = { _, url, _, _ in
            capturedURL.value = url
        }

        let error = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Test"))
        DecodingErrorReporter.report(error: error, url: testURL, httpMethod: "GET")

        XCTAssertEqual(capturedURL.value, testURL)
    }

    func testReportHandlerCapturesMessageCorrectly() {
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

        XCTAssertNotNil(capturedMessage.value)
        XCTAssertTrue(capturedMessage.value!.contains("Missing key: 'fare'"))
    }
    
    // MARK: - Helper Types

    final class SendableBox<T>: @unchecked Sendable {
        var value: T
        init(_ value: T) { self.value = value }
    }
    
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
