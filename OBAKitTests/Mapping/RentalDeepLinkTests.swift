//
//  RentalDeepLinkTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import OTPKit
@testable import OBAKit

/// `RentalDeepLink` answers "where should the Open in <operator> button go?"
///
/// The interesting cases are all absences: no feed publishes GBFS `rental_uris`,
/// so synthesis from the vehicle ID is the live path, and the feed-provided
/// branches exist only to avoid regressing a feed that someday starts sending them.
@Suite
struct RentalDeepLinkTests {

    /// Fixed so `generated_at` renders deterministically.
    private let now = Date(timeIntervalSince1970: 1_785_462_137)
    private let timestamp = "1785462137"

    private func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return items.reduce(into: [:]) { $0[$1.name] = $1.value }
    }

    // MARK: - Synthesis

    @Test func synthesizesLimeVehicleLink() throws {
        let rental = try RentalFixtures.vehicle(id: "lime_seattle:e0762983-6769-4191-903e-7a9e44444ea3")
        let target = try #require(RentalDeepLink.target(for: rental, now: now))

        #expect(target.url.scheme == "limebike")
        #expect(target.url.host == "map")
        #expect(query(target.url)["selected_vehicle_id"] == "e0762983-6769-4191-903e-7a9e44444ea3")
        #expect(query(target.url)["generated_at"] == timestamp)
        #expect(target.storeFallback?.absoluteString == "https://apps.apple.com/app/id1199780189")
        #expect(target.operatorName == "Lime")
    }

    @Test func usesWholeVehicleIDWhenThereIsNoColon() throws {
        let rental = try RentalFixtures.vehicle(id: "bare-id-42")
        let target = try #require(RentalDeepLink.target(for: rental, now: now))

        #expect(query(target.url)["selected_vehicle_id"] == "bare-id-42")
    }

    /// An id that is empty after the network prefix must not produce
    /// `selected_vehicle_id=` with no value — fall back to launching the app.
    @Test func fallsBackToAppLaunchWhenIDIsEmptyAfterPrefix() throws {
        let rental = try RentalFixtures.vehicle(id: "lime_seattle:")
        let target = try #require(RentalDeepLink.target(for: rental, now: now))

        #expect(target.url.scheme == "limebike")
        #expect(query(target.url)["selected_vehicle_id"] == nil)
        #expect(target.storeFallback?.absoluteString == "https://apps.apple.com/app/id1199780189")
    }

    /// The reason this type builds URLs with URLComponents: `.urlQueryAllowed`
    /// would let `&` and `=` through and let a hostile id forge parameters.
    @Test func escapesReservedCharactersInTheVehicleID() throws {
        let nasty = "a&b=c d\u{00e9}?e"
        let rental = try RentalFixtures.vehicle(id: "lime_seattle:\(nasty)")
        let target = try #require(RentalDeepLink.target(for: rental, now: now))

        #expect(query(target.url)["selected_vehicle_id"] == nasty)
        #expect(query(target.url)["generated_at"] == timestamp)
        #expect(query(target.url).count == 2)
    }

    @Test func synthesizesAppLevelLinkForBird() throws {
        let rental = try RentalFixtures.vehicle(id: "bird-seattle-washington:abc", networkId: "bird-seattle-washington")
        let target = try #require(RentalDeepLink.target(for: rental, now: now))

        #expect(target.url.scheme == "bird")
        // Matches the `discovery_uri` Bird's own GBFS feed publishes; a bare
        // `bird:` would be a needless divergence from it.
        #expect(target.url.absoluteString == "bird://")
        #expect(query(target.url)["selected_vehicle_id"] == nil)
        #expect(target.storeFallback?.absoluteString == "https://apps.apple.com/app/id1260842311")
        #expect(target.operatorName == "Bird")
    }

    /// A station id is not a vehicle id; it must never land in `selected_vehicle_id`.
    @Test func stationGetsAppLevelLinkOnly() throws {
        let rental = try RentalFixtures.station(id: "lime_seattle:station-7")
        let target = try #require(RentalDeepLink.target(for: rental, now: now))

        #expect(target.url.scheme == "limebike")
        #expect(query(target.url)["selected_vehicle_id"] == nil)
    }

    // MARK: - Feed data

    @Test func feedProvidedURIWinsOverSynthesis() throws {
        let rental = try RentalFixtures.vehicle(
            id: "lime_seattle:abc",
            rentalUris: ["ios": "https://lime.example/ride/abc"]
        )
        let target = try #require(RentalDeepLink.target(for: rental, now: now))

        #expect(target.url.absoluteString == "https://lime.example/ride/abc")
    }

    /// Branch 1's fallback is the operator web page, not the App Store.
    @Test func feedProvidedURIKeepsTheNetworkURLAsFallback() throws {
        let rental = try RentalFixtures.vehicle(
            id: "lime_seattle:abc",
            networkURL: "https://www.li.me/",
            rentalUris: ["ios": "https://lime.example/ride/abc"]
        )
        let target = try #require(RentalDeepLink.target(for: rental, now: now))

        #expect(target.storeFallback?.absoluteString == "https://www.li.me/")
    }

    /// A feed may publish a deep link without a network block. The pre-synthesis
    /// code showed the button in that case and this must not regress it.
    @Test func feedProvidedURIResolvesWithoutARentalNetwork() throws {
        let rental = try RentalFixtures.vehicle(
            id: "lime_seattle:abc",
            networkId: nil,
            rentalUris: ["ios": "https://lime.example/ride/abc"]
        )
        let target = try #require(RentalDeepLink.target(for: rental, now: now))

        #expect(target.url.absoluteString == "https://lime.example/ride/abc")
        #expect(target.storeFallback == nil)
        #expect(target.operatorName == nil)
    }

    /// A feed URI with no scheme still parses into a non-nil relative `URL`, and
    /// this branch outranks synthesis — so without the scheme check one bad feed
    /// field would replace a working `limebike://` link with an unopenable one.
    @Test func schemelessFeedURIFallsThroughToSynthesis() throws {
        let rental = try RentalFixtures.vehicle(
            id: "lime_seattle:abc",
            rentalUris: ["ios": "lime.example/ride/abc"]
        )
        let target = try #require(RentalDeepLink.target(for: rental, now: now))

        #expect(target.url.scheme == "limebike")
        #expect(query(target.url)["selected_vehicle_id"] == "abc")
    }

    /// Pins the deliberate decision that synthesis outranks `rentalNetwork.url`.
    @Test func synthesisOutranksNetworkURLForKnownOperators() throws {
        let rental = try RentalFixtures.vehicle(id: "lime_seattle:abc", networkURL: "https://www.li.me/")
        let target = try #require(RentalDeepLink.target(for: rental, now: now))

        #expect(target.url.scheme == "limebike")
        #expect(target.storeFallback?.absoluteString == "https://apps.apple.com/app/id1199780189")
    }

    @Test func unknownOperatorFallsThroughToNetworkURL() throws {
        let rental = try RentalFixtures.vehicle(
            id: "veo_seattle:abc",
            networkId: "veo_seattle",
            networkURL: "https://www.veoride.com/"
        )
        let target = try #require(RentalDeepLink.target(for: rental, now: now))

        #expect(target.url.absoluteString == "https://www.veoride.com/")
        #expect(target.storeFallback == nil)
        #expect(target.operatorName == "Veo")
    }

    // MARK: - Absences

    @Test func unknownOperatorWithNoURLReturnsNil() throws {
        let rental = try RentalFixtures.vehicle(id: "veo_seattle:abc", networkId: "veo_seattle")
        #expect(RentalDeepLink.target(for: rental, now: now) == nil)
    }

    @Test func missingRentalNetworkReturnsNil() throws {
        let rental = try RentalFixtures.vehicle(id: "lime_seattle:abc", networkId: nil)
        #expect(RentalDeepLink.target(for: rental, now: now) == nil)
    }

    // MARK: - Feed URI hardening

    /// The button says "Open in Lime". A feed URI that would place a call, compose
    /// a message, or offer an app install is treated as absent, so synthesis runs.
    @Test(arguments: [
        "tel:+12065550100", "TEL:+12065550100", "telprompt:+12065550100",
        "sms:+12065550100", "facetime:someone@example.com", "facetime-audio:someone@example.com",
        "mailto:rides@example.com", "file:///etc/hosts", "javascript:alert(1)",
        "data:text/html,hi", "itms-services://?action=download-manifest&url=https://x.example/m.plist"
    ])
    func rejectedFeedSchemesFallThroughToSynthesis(uri: String) throws {
        let rental = try RentalFixtures.vehicle(id: "lime_seattle:abc", rentalUris: ["ios": uri])
        let target = try #require(RentalDeepLink.target(for: rental, now: now))

        #expect(target.url.scheme == "limebike")
        #expect(query(target.url)["selected_vehicle_id"] == "abc")
    }

    /// A rejected URI with nothing to synthesize from hides the button.
    @Test func rejectedFeedSchemeWithoutAnOperatorHidesTheButton() throws {
        let rental = try RentalFixtures.vehicle(id: "x:1", networkId: nil, rentalUris: ["ios": "tel:+12065550100"])
        #expect(RentalDeepLink.target(for: rental, now: now) == nil)
    }

    @Test func ordinaryFeedSchemesAreKept() throws {
        let rental = try RentalFixtures.vehicle(id: "lime_seattle:abc", rentalUris: ["ios": "lime://ride/abc"])
        let target = try #require(RentalDeepLink.target(for: rental, now: now))
        #expect(target.url.absoluteString == "lime://ride/abc")
    }

    // MARK: - App Store registry

    @Test func synthesizedLinksCarryTheAppStoreID() throws {
        let lime = try #require(RentalDeepLink.target(for: try RentalFixtures.vehicle(id: "lime_seattle:abc"), now: now))
        #expect(lime.appStoreID == "1199780189")

        let bird = try #require(RentalDeepLink.target(
            for: try RentalFixtures.vehicle(id: "bird-seattle-washington:abc", networkId: "bird-seattle-washington"),
            now: now
        ))
        #expect(bird.appStoreID == "1260842311")
    }

    /// A feed-published link fails just as hard when the app is not installed,
    /// so it carries the id too — while its plain fallback stays the web page.
    @Test func feedProvidedURIStillCarriesTheAppStoreID() throws {
        let rental = try RentalFixtures.vehicle(
            id: "lime_seattle:abc",
            networkURL: "https://www.li.me/",
            rentalUris: ["ios": "https://lime.example/ride/abc"]
        )
        let target = try #require(RentalDeepLink.target(for: rental, now: now))

        #expect(target.appStoreID == "1199780189")
        #expect(target.storeFallback?.absoluteString == "https://www.li.me/")
    }

    @Test func webPageTargetCarriesTheAppStoreIDForKnownOperators() throws {
        let rental = try RentalFixtures.vehicle(id: "veo_seattle:abc", networkId: "veo_seattle", networkURL: "https://www.veoride.com/")
        let target = try #require(RentalDeepLink.target(for: rental, now: now))
        #expect(target.appStoreID == "1279820696")
    }

    @Test(arguments: [
        ("lime_seattle", "1199780189"),
        ("bird-seattle-washington", "1260842311"),
        ("veo_seattle", "1279820696"),
        ("spin_dc", "1241808993"),
        ("bolt-portland", "6475395031"),
        ("lyft_sfo", "529379082"),
        ("capital_bikeshare", "1233403073"),
        ("CapitalBikeshare", "1233403073"),
        ("citibike-nyc", "641194843"),
        ("divvy", "1369992600"),
        ("bay_wheels", "1233398899")
    ])
    func registryMatchesKnownOperators(networkID: String, expected: String) {
        #expect(RentalDeepLink.appStoreID(forNetworkID: networkID) == expected)
    }

    /// Conservative on purpose: a leading token that merely starts like a known
    /// system must not borrow its App Store page.
    @Test(arguments: ["capital", "capital_metro", "citi", "bay_area_bikes", "limelight", "unknown_network", ""])
    func registryDoesNotGuess(networkID: String) {
        #expect(RentalDeepLink.appStoreID(forNetworkID: networkID) == nil)
    }
}
