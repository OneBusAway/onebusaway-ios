//
//  RegionCustomFormTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
@testable import OBAKit
@testable import OBAKitCore

/// Tests for `RegionCustomForm.normalizeBaseURL(_:)`, the sole gatekeeper for
/// the Base URL a custom region is saved with.
@MainActor
class RegionCustomFormTests: XCTestCase {

    private func normalize(_ string: String) -> String? {
        RegionCustomForm.normalizeBaseURL(string)?.absoluteString
    }

    func test_normalizeBaseURL_prependsHTTPS() {
        expect(self.normalize("api.tampa.onebusaway.org")) == "https://api.tampa.onebusaway.org"
    }

    func test_normalizeBaseURL_preservesExplicitScheme() {
        expect(self.normalize("http://example.com")) == "http://example.com"
        expect(self.normalize("https://example.com")) == "https://example.com"
    }

    func test_normalizeBaseURL_stripsWhitespace() {
        expect(self.normalize("  api.example.com \n")) == "https://api.example.com"
    }

    /// The field's help text promises `/api/where` is appended automatically,
    /// so a pasted full API URL must not end up with the path doubled.
    func test_normalizeBaseURL_stripsTrailingAPIWhere() {
        expect(self.normalize("https://api.tampa.onebusaway.org/api/where")) == "https://api.tampa.onebusaway.org"
        expect(self.normalize("api.tampa.onebusaway.org/api/where/")) == "https://api.tampa.onebusaway.org"
        expect(self.normalize("example.com/API/WHERE")) == "https://example.com"
    }

    func test_normalizeBaseURL_stripsTrailingSlashes() {
        expect(self.normalize("https://example.com/")) == "https://example.com"
    }

    func test_normalizeBaseURL_rejectsInvalidInput() {
        expect(self.normalize("")).to(beNil())
        expect(self.normalize("   ")).to(beNil())
        expect(self.normalize("ftp://example.com")).to(beNil())
        expect(self.normalize("https://")).to(beNil())

        // Regression: stripping "/api/where" from input where "api" parses as
        // the host (e.g. "api/where" -> "https://api/where") must not leave a
        // scheme-only, host-less URL like "https:" behind unvalidated.
        expect(self.normalize("api/where")).to(beNil())
        expect(self.normalize("https://api/where")).to(beNil())
    }

    // MARK: - normalizeURL (general, no /api/where handling)

    private func normalizeGeneral(_ string: String) -> String? {
        RegionCustomForm.normalizeURL(string)?.absoluteString
    }

    func test_normalizeURL_prependsHTTPS() {
        expect(self.normalizeGeneral("obaco.example.com")) == "https://obaco.example.com"
    }

    func test_normalizeURL_preservesExplicitScheme() {
        expect(self.normalizeGeneral("http://example.com")) == "http://example.com"
    }

    func test_normalizeURL_stripsWhitespaceAndTrailingSlashes() {
        expect(self.normalizeGeneral("  analytics.example.com/ \n")) == "https://analytics.example.com"
    }

    /// Unlike the Base URL field, general URLs keep an `/api/where` path verbatim.
    func test_normalizeURL_doesNotStripAPIWhere() {
        expect(self.normalizeGeneral("example.com/api/where")) == "https://example.com/api/where"
    }

    func test_normalizeURL_rejectsInvalidInput() {
        expect(self.normalizeGeneral("")).to(beNil())
        expect(self.normalizeGeneral("   ")).to(beNil())
        expect(self.normalizeGeneral("ftp://example.com")).to(beNil())
        expect(self.normalizeGeneral("https://")).to(beNil())
    }
}
