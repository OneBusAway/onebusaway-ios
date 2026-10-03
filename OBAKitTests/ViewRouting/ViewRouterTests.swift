//
//  ViewRouterTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
import OBAKitCore

@Suite(.serialized)
@MainActor
final class ViewRouterTests {
    @Test func testNavigationDestinationEnum() {
        let stopIDDest = ViewRouter.NavigationDestination.stopID("1_123")
        switch stopIDDest {
        case .stopID(let id):
            #expect(id == "1_123")
        default:
            Issue.record("Expected .stopID")
        }
    }
}
