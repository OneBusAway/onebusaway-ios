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

    /// Verifies property initialization for EmptyStateView without actions.
    @Test func testEmptyStateViewInitialization() {
        let view = EmptyStateView(
            title: "No Results",
            description: "Try adjusting your search criteria.",
            systemImage: "magnifyingglass"
        )

        #expect(view.title == "No Results")
        #expect(view.description == "Try adjusting your search criteria.")
        #expect(view.systemImage == "magnifyingglass")

        let body = view.body
        _ = body
    }

    /// Verifies property initialization for EmptyStateView with an action button.
    @Test func testEmptyStateViewWithAction() {
        var actionExecuted = false
        let view = EmptyStateView(
            title: "Connection Lost",
            description: "Please check your network and try again.",
            systemImage: "wifi.slash"
        ) {
            Button("Retry") {
                actionExecuted = true
            }
        }

        #expect(view.title == "Connection Lost")
        #expect(view.description == "Please check your network and try again.")
        #expect(view.systemImage == "wifi.slash")

        let body = view.body
        _ = body

        let actionView = view.actions()
        _ = actionView
        #expect(actionExecuted == false)
    }

    /// Verifies that system images used by EmptyStateView are valid SF Symbols.
    @Test func testEmptyStateViewSystemImagesExist() {
        let sampleIcons = ["magnifyingglass", "wifi.slash", "bus", "server.rack"]
        for icon in sampleIcons {
            let image = UIImage(systemName: icon)
            #expect(image != nil, "Expected icon '\(icon)' to exist in system catalog")
        }
    }
}
