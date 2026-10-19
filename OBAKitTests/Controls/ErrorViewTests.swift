//
//  ErrorViewTests.swift
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
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
struct ErrorViewTests {

    private struct TestCustomError: Error, LocalizedError {
        var errorDescription: String? = "Custom test error description"
    }

    /// Verifies property initialization for ErrorView without retry button.
    @Test func testErrorViewInitializationWithoutRetry() {
        let error = TestCustomError()
        let view = ErrorView(
            headline: "Unable to Load Data",
            error: error
        )

        #expect(view.headline == "Unable to Load Data")
        #expect(view.regionName == nil)
        #expect(view.onRetry == nil)

        let body = view.body
        _ = body
    }

    /// Verifies property initialization for ErrorView with retry button and regionName.
    @Test func testErrorViewInitializationWithRetry() {
        var retryTriggered = false
        let error = APIError.cellularDataRestricted
        let view = ErrorView(
            headline: "No Internet Connection",
            error: error,
            regionName: "Puget Sound",
            onRetry: {
                retryTriggered = true
            }
        )

        #expect(view.headline == "No Internet Connection")
        #expect(view.regionName == "Puget Sound")
        #expect(view.onRetry != nil)

        view.onRetry?()
        #expect(retryTriggered == true)

        let body = view.body
        _ = body
    }

    /// Verifies that SF Symbols associated with error classifications are valid system icons.
    @Test func testErrorViewSystemIconsExist() {
        let expectedIcons = [
            "wifi.slash",
            "server.rack",
            "exclamationmark.triangle",
            "lock.shield"
        ]

        for icon in expectedIcons {
            let image = UIImage(systemName: icon)
            #expect(image != nil, "Expected SF Symbol '\(icon)' to exist in system catalog")
        }
    }
}
