//
//  LocalizedAlertErrorTests.swift
//  OBAKitTests
//
//  Copyright (c) Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit

struct LocalizedAlertErrorTests {
    
    private struct MockLocalizedError: LocalizedError {
        var errorDescription: String? = "Mock description"
        var recoverySuggestion: String? = "Mock recovery"
    }
    
    private enum MockStandardError: Error {
        case generic
    }
    
    @Test func testInitWithNilError() {
        let alertError = LocalizedAlertError(error: nil)
        #expect(alertError == nil)
    }
    
    @Test func testInitWithLocalizedError() {
        let originalError = MockLocalizedError()
        let alertError = LocalizedAlertError(error: originalError)
        
        #expect(alertError != nil)
        #expect(alertError?.errorDescription == "Mock description")
        #expect(alertError?.recoverySuggestion == "Mock recovery")
    }
    
    @Test func testInitWithStandardError() {
        let originalError = MockStandardError.generic
        let alertError = LocalizedAlertError(error: originalError)
        
        #expect(alertError != nil)
        // Standard errors provide a localizedDescription based on their type
        #expect(alertError?.errorDescription == originalError.localizedDescription)
        #expect(alertError?.recoverySuggestion == nil)
    }
}
