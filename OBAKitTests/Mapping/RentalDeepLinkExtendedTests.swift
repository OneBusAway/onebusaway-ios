//
//  RentalDeepLinkExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OTPKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class RentalDeepLinkExtendedTests: OBATestCase {

    private func makeRental(
        networkID: String? = nil,
        networkURL: String? = nil,
        iosURI: String? = nil
    ) throws -> VehicleRental {
        let rentalUris: [String: String]?
        if let iosURI {
            rentalUris = ["ios": iosURI]
        } else {
            rentalUris = nil
        }
        return try RentalFixtures.vehicle(
            id: "rental_test_1",
            networkId: networkID,
            networkURL: networkURL,
            rentalUris: rentalUris
        )
    }

    @Test func `App Store ID resolves correctly for known token operators`() {
        #expect(RentalDeepLink.appStoreID(forNetworkID: "lime_seattle") == "1199780189")
        #expect(RentalDeepLink.appStoreID(forNetworkID: "bird-portland") == "1260842311")
        #expect(RentalDeepLink.appStoreID(forNetworkID: "veo_chicago") == "1279820696")
        #expect(RentalDeepLink.appStoreID(forNetworkID: "spin_dc") == "1241808993")
        #expect(RentalDeepLink.appStoreID(forNetworkID: "bolt-austin") == "6475395031")
        #expect(RentalDeepLink.appStoreID(forNetworkID: "lyft_denver") == "529379082")
    }

    @Test func `App Store ID resolves for docked system prefixes`() {
        #expect(RentalDeepLink.appStoreID(forNetworkID: "capital_bikeshare_dc") == "1233403073")
        #expect(RentalDeepLink.appStoreID(forNetworkID: "citibike-nyc") == "641194843")
        #expect(RentalDeepLink.appStoreID(forNetworkID: "divvy_chicago") == "1369992600")
        #expect(RentalDeepLink.appStoreID(forNetworkID: "bay_wheels_sf") == "1233398899")
    }

    @Test func `App Store ID returns nil for unrecognized operators`() {
        #expect(RentalDeepLink.appStoreID(forNetworkID: "unknown_mobility_corp") == nil)
        #expect(RentalDeepLink.appStoreID(forNetworkID: "random_system") == nil)
    }

    @Test func `App Store URL formats correctly with https apps apple com`() {
        let url = RentalDeepLink.appStoreURL(forID: "1199780189")
        #expect(url?.absoluteString == "https://apps.apple.com/app/id1199780189")
    }

    @Test func `Feed iOS URI overrides synthesis when valid and safe`() throws {
        let rental = try makeRental(
            networkID: "lime_seattle",
            iosURI: "https://lime.bike/ride/custom_trip"
        )
        let target = RentalDeepLink.target(for: rental)

        let resolved = try #require(target)
        #expect(resolved.url.absoluteString == "https://lime.bike/ride/custom_trip")
        #expect(resolved.appStoreID == "1199780189")
    }

    @Test func `Feed iOS URI rejects unsafe and forbidden schemes`() throws {
        let unsafeSchemes = [
            "tel:1234567890",
            "sms:1234567890",
            "facetime:user@example.com",
            "mailto:help@example.com",
            "file:///etc/passwd",
            "javascript:alert(1)",
            "itms-services://?action=download-manifest"
        ]

        for unsafeURI in unsafeSchemes {
            let rental = try makeRental(
                networkID: "lime_seattle",
                iosURI: unsafeURI
            )
            let target = RentalDeepLink.target(for: rental)
            let resolved = try #require(target)
            // Unsafe feed URI is rejected, falling back to synthesized lime link
            #expect(resolved.url.absoluteString == "limebike://map")
        }
    }

    @Test func `Missing feed URI synthesizes app launch link for known operators`() throws {
        let limeRental = try makeRental(networkID: "lime_seattle")
        let limeTarget = try #require(RentalDeepLink.target(for: limeRental))
        #expect(limeTarget.url.absoluteString == "limebike://map")
        #expect(limeTarget.appStoreID == "1199780189")
        #expect(limeTarget.storeFallback?.absoluteString == "https://apps.apple.com/app/id1199780189")

        let birdRental = try makeRental(networkID: "bird_portland")
        let birdTarget = try #require(RentalDeepLink.target(for: birdRental))
        #expect(birdTarget.url.absoluteString == "bird://")
        #expect(birdTarget.appStoreID == "1260842311")
    }

    @Test func `Unknown operator falls back to published network website URL`() throws {
        let rental = try makeRental(
            networkID: "local_bike_share",
            networkURL: "https://localbikeshare.example.org"
        )
        let target = try #require(RentalDeepLink.target(for: rental))

        #expect(target.url.absoluteString == "https://localbikeshare.example.org")
        #expect(target.storeFallback == nil)
        #expect(target.appStoreID == nil)
    }

    @Test func `Empty rental without network or feed URI returns nil target`() throws {
        let rental = try makeRental()
        #expect(RentalDeepLink.target(for: rental) == nil)
    }
}
