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

    /// Verifies property initialization for ErrorView convenience initializer without retry button.
    @Test func testErrorViewInitializationWithoutRetry() {
        let error = TestCustomError()
        let view = ErrorView(
            headline: "Unable to Load Data",
            error: error
        )

        #expect(view.headline == "Unable to Load Data")
        #expect(view.regionName == nil)
        #expect(view.onRetry == nil)
    }

    /// Verifies that ErrorView.iconName(for:) maps classified APIErrors and generic errors to the expected SF Symbols.
    @Test func testErrorViewIconMapping() {
        #expect(ErrorView.iconName(for: APIError.cellularDataRestricted) == "wifi.slash")
        #expect(ErrorView.iconName(for: APIError.networkFailure(URLError(.notConnectedToInternet))) == "wifi.slash")
        #expect(ErrorView.iconName(for: APIError.serverError(regionName: "Puget Sound")) == "server.rack")
        #expect(ErrorView.iconName(for: APIError.serverUnavailable(regionName: "Puget Sound", statusCode: 503)) == "server.rack")
        #expect(ErrorView.iconName(for: APIError.captivePortal) == "lock.shield")
        #expect(ErrorView.iconName(for: APIError.invalidResponseData(regionName: "Puget Sound")) == "exclamationmark.triangle")
        #expect(ErrorView.iconName(for: TestCustomError()) == "exclamationmark.triangle")
    }
}
