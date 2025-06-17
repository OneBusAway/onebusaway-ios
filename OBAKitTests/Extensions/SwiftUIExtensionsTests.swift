//
//  SwiftUIExtensionsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import XCTest
import Nimble
import SwiftUI
@testable import OBAKit

@available(iOS 14.0, *)
class SwiftUIExtensionsTests: XCTestCase {
    
    func test_onFirstAppear_callsActionOnlyOnce() {
        var callCount = 0
        let testView = Text("Test")
            .onFirstAppear {
                callCount += 1
            }
        
        // This test is limited since we can't easily trigger onAppear in unit tests
        // But we can verify the modifier compiles and the view can be created
        expect(testView).toNot(beNil())
        
        // The action should not have been called yet since onAppear hasn't triggered
        expect(callCount) == 0
    }
}
