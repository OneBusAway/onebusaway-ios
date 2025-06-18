//
//  CodableExtensionsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import XCTest
import Nimble
@testable import OBAKitCore

class CodableExtensionsTests: XCTestCase {
    
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
    
    func test_decodeGarbageURL_validURL() throws {
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
        
        expect(result.validURL?.absoluteString) == "https://example.com"
        expect(result.invalidURL).to(beNil()) // Invalid URL becomes nil
        expect(result.blankURL).to(beNil()) // Blank string becomes nil
        expect(result.nilURL).to(beNil()) // Null value becomes nil
    }
    
    func test_decodeGarbageURL_missingKey() throws {
        let json = """
        {
            "validURL": "https://example.com"
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let result = try decoder.decode(TestStruct.self, from: data)
        
        expect(result.validURL?.absoluteString) == "https://example.com"
        expect(result.invalidURL).to(beNil())
        expect(result.blankURL).to(beNil())
        expect(result.nilURL).to(beNil())
    }
    
    func test_decodeGarbageURL_whitespaceURL() throws {
        let json = """
        {
            "blankURL": "   ",
            "validURL": "https://example.com"
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let result = try decoder.decode(TestStruct.self, from: data)
        
        expect(result.validURL?.absoluteString) == "https://example.com"
        expect(result.blankURL).to(beNil()) // Whitespace-only string should become nil
    }
    
    func test_decodeGarbageURL_malformedURL() throws {
        let json = """
        {
            "invalidURL": "http://[malformed",
            "validURL": "https://example.com"
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let result = try decoder.decode(TestStruct.self, from: data)
        
        expect(result.validURL?.absoluteString) == "https://example.com"
        expect(result.invalidURL).to(beNil()) // Malformed URL becomes nil
    }
    
    func test_decodeGarbageURL_pathURL() throws {
        let json = """
        {
            "validURL": "/path/to/resource"
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let result = try decoder.decode(TestStruct.self, from: data)
        
        expect(result.validURL?.absoluteString) == "/path/to/resource"
        expect(result.validURL?.path) == "/path/to/resource"
    }
}
