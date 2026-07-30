//
//  CodableExtensionsTests.swift
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
final class CodableExtensionsTests {
    
    struct TestStruct: Codable {
        let validURL: URL?
        let invalidURL: URL?
        let blankURL: URL?
        let nilURL: URL?
        
        enum CodingKeys: String, CodingKey {
            case validURL, invalidURL, blankURL, nilURL
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            validURL = try container.decodeGarbageURL(forKey: .validURL)
            invalidURL = try container.decodeGarbageURL(forKey: .invalidURL)
            blankURL = try container.decodeGarbageURL(forKey: .blankURL)
            nilURL = try container.decodeGarbageURL(forKey: .nilURL)
        }
    }
    
    @Test func `Decode garbage URL valid URL`() throws {
        let json = """
        {
            "validURL": "https://example.com",
            "invalidURL": "not a url",
            "blankURL": "",
            "nilURL": null
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let result = try decoder.decode(TestStruct.self, from: data)
        
        #expect(result.validURL?.absoluteString == "https://example.com")
        #expect(result.invalidURL == nil)  // Invalid URL becomes nil
        #expect(result.blankURL == nil)  // Blank string becomes nil
        #expect(result.nilURL == nil)  // Null value becomes nil
    }
    
    @Test func `Decode garbage URL missing key`() throws {
        let json = """
        {
            "validURL": "https://example.com"
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let result = try decoder.decode(TestStruct.self, from: data)
        
        #expect(result.validURL?.absoluteString == "https://example.com")
        #expect(result.invalidURL == nil)
        #expect(result.blankURL == nil)
        #expect(result.nilURL == nil)
    }
    
    @Test func `Decode garbage URL whitespace URL`() throws {
        let json = """
        {
            "blankURL": "   ",
            "validURL": "https://example.com"
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let result = try decoder.decode(TestStruct.self, from: data)
        
        #expect(result.validURL?.absoluteString == "https://example.com")
        #expect(result.blankURL == nil)  // Whitespace-only string should become nil
    }
    
    @Test func `Decode garbage URL malformed URL`() throws {
        let json = """
        {
            "invalidURL": "http://[malformed",
            "validURL": "https://example.com"
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let result = try decoder.decode(TestStruct.self, from: data)
        
        #expect(result.validURL?.absoluteString == "https://example.com")
        #expect(result.invalidURL == nil)  // Malformed URL becomes nil
    }
    
    @Test func `Decode garbage URL path URL`() throws {
        let json = """
        {
            "validURL": "/path/to/resource"
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let result = try decoder.decode(TestStruct.self, from: data)
        
        #expect(result.validURL?.absoluteString == "/path/to/resource")
        #expect(result.validURL?.path == "/path/to/resource")
    }
}
