//
//  EmptyStateViewTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import SwiftUI
import UIKit
@testable import OBAKit

@MainActor
@Suite(.serialized)
struct EmptyStateViewTests {

    /// Verifies property initialization for EmptyStateView convenience initializer without actions.
    @Test func testEmptyStateViewInitialization() {
        let view = EmptyStateView(
            title: "No Results",
            description: "Try adjusting your search criteria.",
            systemImage: "magnifyingglass"
        )

        #expect(view.title == "No Results")
        #expect(view.description == "Try adjusting your search criteria.")
        #expect(view.systemImage == "magnifyingglass")
    }
}
