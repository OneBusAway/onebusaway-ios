//
//  RegionCustomFormTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
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

    // MARK: - RegionCustomFormError

    /// Checks the message in the host's localization. Every translation keeps the
    /// URL as `%1$@` and the error as `%2$@`, so the order check holds whichever one
    /// that is. The key check reads `en.lproj` directly, because `OBALoc` falls back
    /// to its English literal and would hide a missing key.
    @Test func `Server validation error names the base URL and then the underlying error`() throws {
        let baseURL = try #require(URL(string: "https://api.tampa.onebusaway.org"))
        let underlying = NSError(domain: "RegionCustomFormTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "The server sent back nonsense."])

        let message = try #require(RegionCustomFormError.serverValidationFailed(baseURL: baseURL, underlyingError: underlying).errorDescription)

        let urlRange = try #require(message.range(of: "https://api.tampa.onebusaway.org"))
        let errorRange = try #require(message.range(of: "The server sent back nonsense."))
        #expect(urlRange.lowerBound < errorRange.lowerBound)

        let english = try #require(Bundle.obaKit.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:)))
        let key = "custom_region_builder_controller.server_validation_error_fmt"
        #expect(english.localizedString(forKey: key, value: "MISSING", table: nil) != "MISSING")
    }

    // MARK: - Saving

    private struct ProviderFailure: Error {}

    /// Serves an agency list for the server check and records what is added.
    private final class RecordingRegionProvider: RegionProvider {
        var allRegions: [Region] = []
        var currentRegion: Region?
        var currentLocation: CLLocation?
        var automaticallySelectRegion = false

        var agencies: [AgencyWithCoverage] = []
        var validationFailure: Error?
        var addFailure: Error?
        private(set) var added: [Region] = []

        func refreshRegions() async throws {}
        func setCurrentRegion(to newRegion: Region) async throws {}
        func delete(customRegion region: Region) async throws {}
        func isTripPlanningEnabled(for region: Region) -> Bool { false }
        func setTripPlanningEnabled(_ enabled: Bool, for region: Region) {}

        func add(customRegion newRegion: Region) async throws {
            if let addFailure { throw addFailure }
            added.append(newRegion)
        }

        func fetchAgenciesWithCoverage(baseURL: URL) async throws -> [AgencyWithCoverage] {
            if let validationFailure { throw validationFailure }
            return agencies
        }
    }

    private let baseURL = URL(string: "https://api.tampa.onebusaway.org")!
    private let serviceArea = MKMapRect(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 27.95, longitude: -82.46), latitudinalMeters: 2000, longitudinalMeters: 2000))

    /// A provider whose server reports the agencies in `agencies_with_coverage.json`.
    private func providerWithAgencies() throws -> RecordingRegionProvider {
        let provider = RecordingRegionProvider()
        provider.agencies = try Fixtures.loadRESTAPIPayload(type: [AgencyWithCoverage].self, fileName: "agencies_with_coverage.json")
        return provider
    }

    private func save(name: String, editing: Region? = nil, to provider: RecordingRegionProvider) async throws {
        try await RegionCustomForm.save(
            name: name,
            baseURL: baseURL,
            serviceArea: serviceArea,
            sidecarURL: nil,
            umamiURL: nil,
            umamiID: "",
            editing: editing,
            to: provider
        )
    }

    @Test func `An unnamed region is named after its server's first agency`() async throws {
        let provider = try providerWithAgencies()
        let firstAgency = try #require(provider.agencies.first?.agency?.name)
        #expect(!firstAgency.isEmpty)

        try await save(name: "", to: provider)

        #expect(provider.added.count == 1)
        #expect(provider.added.first?.name == firstAgency)
    }

    @Test func `A name of only spaces counts as no name`() async throws {
        let provider = try providerWithAgencies()
        let firstAgency = try #require(provider.agencies.first?.agency?.name)

        try await save(name: "  \n ", to: provider)

        #expect(provider.added.first?.name == firstAgency)
    }

    @Test func `A typed name is kept, without surrounding spaces`() async throws {
        let provider = try providerWithAgencies()

        try await save(name: "  Tampa Test ", to: provider)

        #expect(provider.added.first?.name == "Tampa Test")
    }

    /// The form shows only the name, URLs and service area. Saving an edit must
    /// not reset the rest, or the region would get a new identifier and lose its
    /// trip planner.
    @Test func `Editing keeps the region's identifier, contact email and trip planner`() async throws {
        let provider = try providerWithAgencies()
        let existing = Region(
            name: "Tampa",
            OBABaseURL: baseURL,
            coordinateRegion: MKCoordinateRegion(serviceArea),
            contactEmail: "rider@example.org",
            regionIdentifier: 4242,
            openTripPlannerURL: URL(string: "https://otp.example.org/otp/")!
        )

        try await save(name: "Tampa", editing: existing, to: provider)

        let saved = try #require(provider.added.first)
        #expect(saved.regionIdentifier == 4242)
        #expect(saved.contactEmail == "rider@example.org")
        #expect(saved.openTripPlannerURL?.absoluteString == "https://otp.example.org/otp/")
    }

    @Test func `The sidecar and analytics servers are saved with the region`() async throws {
        let provider = try providerWithAgencies()
        let sidecar = try #require(URL(string: "https://obaco.example.org"))
        let analytics = try #require(URL(string: "https://analytics.example.org"))

        try await RegionCustomForm.save(
            name: "Tampa",
            baseURL: baseURL,
            serviceArea: serviceArea,
            sidecarURL: sidecar,
            umamiURL: analytics,
            umamiID: "site-123",
            editing: nil,
            to: provider
        )

        let saved = try #require(provider.added.first)
        #expect(saved.sidecarBaseURL == sidecar)
        #expect(saved.umamiAnalytics?.url == analytics)
        #expect(saved.umamiAnalytics?.id == "site-123")
    }

    /// The view keeps the form open and shows this error.
    @Test func `A server that fails the check saves nothing and names the base URL`() async throws {
        let provider = RecordingRegionProvider()
        provider.validationFailure = ProviderFailure()

        await #expect {
            try await save(name: "Tampa", to: provider)
        } throws: { error in
            guard case .serverValidationFailed(let failedURL, let underlying) = error as? RegionCustomFormError else { return false }
            return failedURL == baseURL && underlying is ProviderFailure
        }
        #expect(provider.added.isEmpty)
    }

    /// Only the server check is reported as an unreachable server. A failure to
    /// store the region is shown as it is.
    @Test func `A region that can't be stored shows the provider's own error`() async throws {
        let provider = try providerWithAgencies()
        provider.addFailure = ProviderFailure()

        await #expect(throws: ProviderFailure.self) {
            try await save(name: "Tampa", to: provider)
        }
    }
}
