//
//  RegionCustomFormTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Tests for `RegionCustomForm.normalizeBaseURL(_:)`, the sole gatekeeper for
/// the Base URL a custom region is saved with.
@MainActor
@Suite(.serialized)
final class RegionCustomFormTests {

    private func normalize(_ string: String) -> String? {
        RegionCustomForm.normalizeBaseURL(string)?.absoluteString
    }

    @Test func `Normalize base URL prepends HTTPS`() {
        #expect(self.normalize("api.tampa.onebusaway.org") == "https://api.tampa.onebusaway.org")
    }

    @Test func `Normalize base URL preserves explicit scheme`() {
        #expect(self.normalize("http://example.com") == "http://example.com")
        #expect(self.normalize("https://example.com") == "https://example.com")
    }

    @Test func `Normalize base URL strips whitespace`() {
        #expect(self.normalize("  api.example.com \n") == "https://api.example.com")
    }

    /// The field's help text promises `/api/where` is appended automatically,
    /// so a pasted full API URL must not end up with the path doubled.
    @Test func `Normalize base URL strips trailing API where`() {
        #expect(self.normalize("https://api.tampa.onebusaway.org/api/where") == "https://api.tampa.onebusaway.org")
        #expect(self.normalize("api.tampa.onebusaway.org/api/where/") == "https://api.tampa.onebusaway.org")
        #expect(self.normalize("example.com/API/WHERE") == "https://example.com")
    }

    @Test func `Normalize base URL strips trailing slashes`() {
        #expect(self.normalize("https://example.com/") == "https://example.com")
    }

    @Test func `Normalize base URL rejects invalid input`() {
        #expect(self.normalize("") == nil)
        #expect(self.normalize("   ") == nil)
        #expect(self.normalize("ftp://example.com") == nil)
        #expect(self.normalize("https://") == nil)

        // Regression: stripping "/api/where" from input where "api" parses as
        // the host (e.g. "api/where" -> "https://api/where") must not leave a
        // scheme-only, host-less URL like "https:" behind unvalidated.
        #expect(self.normalize("api/where") == nil)
        #expect(self.normalize("https://api/where") == nil)
    }

    // MARK: - normalizeURL (general, no /api/where handling)

    private func normalizeGeneral(_ string: String) -> String? {
        RegionCustomForm.normalizeURL(string)?.absoluteString
    }

    @Test func `Normalize URL prepends HTTPS`() {
        #expect(self.normalizeGeneral("obaco.example.com") == "https://obaco.example.com")
    }

    @Test func `Normalize URL preserves explicit scheme`() {
        #expect(self.normalizeGeneral("http://example.com") == "http://example.com")
    }

    @Test func `Normalize URL strips whitespace and trailing slashes`() {
        #expect(self.normalizeGeneral("  analytics.example.com/ \n") == "https://analytics.example.com")
    }

    /// Unlike the Base URL field, general URLs keep an `/api/where` path verbatim.
    @Test func `Normalize URL does not strip API where`() {
        #expect(self.normalizeGeneral("example.com/api/where") == "https://example.com/api/where")
    }

    @Test func `Normalize URL rejects invalid input`() {
        #expect(self.normalizeGeneral("") == nil)
        #expect(self.normalizeGeneral("   ") == nil)
        #expect(self.normalizeGeneral("ftp://example.com") == nil)
        #expect(self.normalizeGeneral("https://") == nil)
    }
}
