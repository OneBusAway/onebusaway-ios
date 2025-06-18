//
//  FoundationExtensionsTests.swift
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

class FoundationExtensionsTests: XCTestCase {
    
    func test_Bundle_appName() {
        let bundle = Bundle.main
        let appName = bundle.appName
        
        // This will vary by app, but should not be empty for main bundle
        expect(appName).toNot(beEmpty())
    }
    
    func test_Bundle_bundleIdentifier_extension() {
        let bundle = Bundle.main
        // Test that our bundleIdentifier extension works by getting the CFBundleIdentifier value
        let bundleIdentifier = bundle.object(forInfoDictionaryKey: "CFBundleIdentifier") as? String
        
        expect(bundleIdentifier).toNot(beNil())
        expect(bundleIdentifier).toNot(beEmpty())
        expect(bundleIdentifier).to(contain("."))
    }
    
    func test_Bundle_appVersion() {
        let bundle = Bundle.main
        let appVersion = bundle.appVersion
        
        expect(appVersion).toNot(beEmpty())
    }
    
    func test_Bundle_copyright() {
        let bundle = Bundle.main
        let copyright = bundle.copyright
        
        // This may be empty in test bundles, but should not crash
        expect(copyright).toNot(beNil())
    }
    
    func test_Bundle_userActivityTypes() {
        let bundle = Bundle.main
        let userActivityTypes = bundle.userActivityTypes
        
        // This may be nil, but should not crash
        if let types = userActivityTypes {
            expect(types).to(beAnInstanceOf([String].self))
        }
    }
    
    func test_Bundle_donationsEnabled() {
        let bundle = Bundle.main
        let donationsEnabled = bundle.donationsEnabled
        
        // This should return a boolean value without crashing
        expect(donationsEnabled).to(beAnInstanceOf(Bool.self))
    }
    
    func test_Bundle_donationManagementPortal() {
        let bundle = Bundle.main
        let portal = bundle.donationManagementPortal
        
        // This may be nil, but should not crash
        if let portalURL = portal {
            expect(portalURL).to(beAnInstanceOf(URL.self))
        }
    }
    
    func test_Bundle_extensionURLScheme() {
        let bundle = Bundle.main
        let scheme = bundle.extensionURLScheme
        
        // This may be nil, but should not crash
        if let urlScheme = scheme {
            expect(urlScheme).to(beAnInstanceOf(String.self))
            expect(urlScheme).toNot(beEmpty())
        }
    }
    
    func test_Bundle_bundledRegionsFileName() {
        let bundle = Bundle.main
        let fileName = bundle.bundledRegionsFileName
        
        // This may be nil, but should not crash
        if let name = fileName {
            expect(name).to(beAnInstanceOf(String.self))
            expect(name).toNot(beEmpty())
        }
    }
    
    func test_Bundle_bundledRegionsFilePath() {
        let bundle = Bundle.main
        let filePath = bundle.bundledRegionsFilePath
        
        // This may be nil, but should not crash
        if let path = filePath {
            expect(path).to(beAnInstanceOf(String.self))
            expect(path).toNot(beEmpty())
        }
    }
    
    func test_Bundle_regionsServerBaseAddress() {
        let bundle = Bundle.main
        let baseAddress = bundle.regionsServerBaseAddress
        
        // This may be nil, but should not crash
        if let url = baseAddress {
            expect(url).to(beAnInstanceOf(URL.self))
        }
    }
    
    func test_Bundle_regionsServerAPIPath() {
        let bundle = Bundle.main
        let apiPath = bundle.regionsServerAPIPath
        
        // This may be nil, but should not crash
        if let path = apiPath {
            expect(path).to(beAnInstanceOf(String.self))
            expect(path).toNot(beEmpty())
        }
    }
    
    func test_Bundle_restServerAPIKey() {
        let bundle = Bundle.main
        let apiKey = bundle.restServerAPIKey
        
        // This may be nil, but should not crash
        if let key = apiKey {
            expect(key).to(beAnInstanceOf(String.self))
            expect(key).toNot(beEmpty())
        }
    }
    
    func test_Bundle_appGroup() {
        let bundle = Bundle.main
        let appGroup = bundle.appGroup
        
        // This may be nil, but should not crash
        if let group = appGroup {
            expect(group).to(beAnInstanceOf(String.self))
            expect(group).toNot(beEmpty())
        }
    }
}
