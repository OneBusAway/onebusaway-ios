//
//  UnstructuredErrorTests.swift
//  OBAKitCoreTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

@Suite(.serialized)
final class UnstructuredErrorTests {
    
    @Test func Initialization sets properties correctly() {
        let error = UnstructuredError("Something went wrong", recoverySuggestion: "Try again later")
        
        #expect(error.errorDescription == "Something went wrong")
        #expect(error.recoverySuggestion == "Try again later")
    }
    
    @Test func Initialization without recovery suggestion() {
        let error = UnstructuredError("Only description")
        
        #expect(error.errorDescription == "Only description")
        #expect(error.recoverySuggestion == nil)
    }
}
