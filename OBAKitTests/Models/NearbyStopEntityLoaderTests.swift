//
//  NearbyStopEntityLoaderTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import os
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// The order visual intelligence lists stops in (#1555).
@Suite(.serialized)
struct NearbyStopRankingTests {
    private let rider = CLLocation(latitude: 47.6, longitude: -122.3)

    /// `count` stops due north of the rider, about 110 m apart, `s1` nearest.
    private func stopsNorth(_ count: Int, codes: [Int: String] = [:]) -> [Stop] {
        (1...count).map { index in
            Stop(
                id: "s\(index)",
                name: "Stop \(index)",
                code: codes[index] ?? "",
                location: CLLocation(latitude: 47.6 + 0.001 * Double(index), longitude: -122.3),
                regionIdentifier: 1
            )
        }
    }

    @Test func `Stops come closest first, at most ten`() {
        let stops = stopsNorth(12).reversed()

        let ranked = NearbyStopRanking.rank(Array(stops), from: rider, recognizedText: [])

        #expect(ranked.map(\.id) == (1...10).map { "s\($0)" })
    }

    /// The sign's stop is the one the rider is looking at, even when the
    /// server lists nearer ones and it falls outside the ten.
    @Test func `A stop code read off the sign puts that stop first`() {
        let stops = stopsNorth(12, codes: [12: "99610"])

        let ranked = NearbyStopRanking.rank(stops, from: rider, recognizedText: ["Capitol Hill", "Stop #99610"])

        #expect(ranked.map(\.id) == ["s12"] + (1...9).map { "s\($0)" })
    }

    /// Route numbers on the same sign would otherwise pick a stop.
    @Test func `A code shorter than three characters is not matched`() {
        let stops = stopsNorth(5, codes: [5: "49"])

        let ranked = NearbyStopRanking.rank(stops, from: rider, recognizedText: ["49", "Route 49"])

        #expect(ranked.map(\.id) == ["s1", "s2", "s3", "s4", "s5"])
    }

    @Test func `A code matches whatever its case on the sign`() {
        let stops = stopsNorth(3, codes: [3: "A1B"])

        let ranked = NearbyStopRanking.rank(stops, from: rider, recognizedText: ["stop a1b"])

        #expect(ranked.map(\.id) == ["s3", "s1", "s2"])
    }

    /// "Stop 9961" contains the code 996 but doesn't show it.
    @Test func `A code matches only as a whole word`() {
        let stops = stopsNorth(3, codes: [3: "996"])

        let ranked = NearbyStopRanking.rank(stops, from: rider, recognizedText: ["Stop 9961"])

        #expect(ranked.map(\.id) == ["s1", "s2", "s3"])
    }
}

/// What visual intelligence gets: the stops near the rider from the region's
/// server, as stop entities a tap can open.
@Suite(.serialized)
final class NearbyStopEntityLoaderTests: OBATestCase {
    /// Next to `1_10914` in `stops_for_location_seattle.json`.
    private let rider = CLLocation(latitude: 47.6564, longitude: -122.3121)

    /// What the system might label a photo of a bus stop; any transit label passes the gate.
    static let busStopLabels = ["bus stop"]

    override init() async throws {
        try await super.init()
        ResolvedRegionStore(userDefaults: userDefaults).write(Fixtures.pugetSoundRegion)
    }

    private func loader(dataLoader: MockDataLoader, location: CLLocation?) -> NearbyStopEntityLoader {
        NearbyStopEntityLoader(
            userDefaults: userDefaults,
            bundledRegionsFilePath: nil,
            apiKey: apiKey,
            appVersion: appVersion,
            dataLoader: dataLoader,
            currentLocation: { location }
        )
    }

    private func mockStops(_ dataLoader: MockDataLoader, statusCode: Int = 200) {
        let data = statusCode == 200 ? Fixtures.loadData(file: "stops_for_location_seattle.json") : Data("{}".utf8)
        dataLoader.mock(data: data, statusCode: statusCode) { request in
            request.url?.path.hasSuffix("/stops-for-location.json") ?? false
        }
    }

    @Test func `The nearest stops come back as entities, closest first`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        mockStops(dataLoader)

        let entities = await loader(dataLoader: dataLoader, location: rider).entities(labels: Self.busStopLabels, recognizedText: [])

        #expect(entities.count == NearbyStopRanking.resultLimit)
        #expect(entities.first?.stopID == "1_10914")
        let distances = entities.compactMap { entity in
            entity.latitude.flatMap { lat in entity.longitude.map { CLLocation(latitude: lat, longitude: $0).distance(from: rider) } }
        }
        #expect(distances.count == entities.count)
        #expect(distances == distances.sorted())
        #expect(entities.allSatisfy { $0.regionID == Fixtures.pugetSoundRegion.regionIdentifier })
    }

    /// Visual intelligence asks for an image; Spotlight and Shortcuts keep
    /// the plain entity they had.
    @Test func `Camera results carry the stop's transport glyph, other entities don't`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        mockStops(dataLoader)

        let entities = await loader(dataLoader: dataLoader, location: rider).entities(labels: Self.busStopLabels, recognizedText: [])
        let first = try #require(entities.first)

        #expect(first.imageData != nil)
        #expect(first.displayRepresentation.image != nil)

        let stop = Stop(id: "1_10914", name: "Stop", code: "10914", location: rider, regionIdentifier: 1)
        let spotlight = StopEntityMapping.entity(for: stop, regionID: 1)
        #expect(spotlight.imageData == nil)
        #expect(spotlight.displayRepresentation.image == nil)
    }

    /// A stop decoded without its routes has no route type to draw; asking for
    /// one would trap.
    @Test func `A stop without routes still gets a glyph`() {
        let stop = Stop(id: "1_10914", name: "Stop", code: "10914", location: rider, regionIdentifier: 1)
        // As decoded from a payload with no references; the initializer sets [].
        stop.routes = nil

        let entity = StopEntityMapping.entity(for: stop, regionID: 1, includesImage: true)

        #expect(entity.imageData != nil)
    }

    /// A tapped result reaches `OpenStopIntent` by its id, which must still
    /// name this stop in this region.
    @Test func `A result opens its own stop in its own region`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        mockStops(dataLoader)

        let entities = await loader(dataLoader: dataLoader, location: rider).entities(labels: Self.busStopLabels, recognizedText: [])
        let first = try #require(entities.first)

        let destination = try #require(StopEntityMapping.destination(fromIdentifier: first.id))
        #expect(destination.stopID == "1_10914")
        #expect(destination.regionID == Fixtures.pugetSoundRegion.regionIdentifier)
        #expect(first.destination.stopID == "1_10914")
    }

    @Test func `The sign's stop code moves that stop first`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        mockStops(dataLoader)

        let entities = await loader(dataLoader: dataLoader, location: rider).entities(labels: Self.busStopLabels, recognizedText: ["Stop # 10917"])

        #expect(entities.first?.stopID == "1_10917")
    }

    /// No stub: a request would end the test in `MockDataLoader`.
    @Test func `No region gives no stops and no request`() async {
        ResolvedRegionStore(userDefaults: userDefaults).write(nil)

        let entities = await loader(dataLoader: MockDataLoader(testName: name), location: rider).entities(labels: Self.busStopLabels, recognizedText: [])

        #expect(entities.isEmpty)
    }

    /// No stub: a request would end the test in `MockDataLoader`.
    @Test func `No location gives no stops and no request`() async {
        let entities = await loader(dataLoader: MockDataLoader(testName: name), location: nil).entities(labels: Self.busStopLabels, recognizedText: [])

        #expect(entities.isEmpty)
    }

    /// No stub: a request would end the test in `MockDataLoader`.
    @Test func `An unrelated search asks for no location and makes no request`() async {
        let locationRequests = OSAllocatedUnfairLock(initialState: 0)
        let loader = NearbyStopEntityLoader(
            userDefaults: userDefaults,
            bundledRegionsFilePath: nil,
            apiKey: apiKey,
            appVersion: appVersion,
            dataLoader: MockDataLoader(testName: name),
            currentLocation: { [rider] in
                locationRequests.withLock { $0 += 1 }
                return rider
            }
        )

        let entities = await loader.entities(labels: ["dog", "pet"], recognizedText: ["Good boy"])

        #expect(entities.isEmpty)
        #expect(locationRequests.withLock { $0 } == 0)
    }

    /// The camera would show an error; an empty list shows nothing.
    @Test func `A failed fetch gives no stops`() async {
        let dataLoader = MockDataLoader(testName: name)
        mockStops(dataLoader, statusCode: 500)

        let entities = await loader(dataLoader: dataLoader, location: rider).entities(labels: Self.busStopLabels, recognizedText: [])

        #expect(entities.isEmpty)
    }
}

/// Visual intelligence asks for every search; only a transit sign gets stops.
@Suite(.serialized)
struct TransitSignGateTests {
    @Test func `A transit label passes, whatever the text`() {
        #expect(TransitSignGate.looksLikeTransitSign(labels: ["Bus Stop"], recognizedText: []))
        #expect(TransitSignGate.looksLikeTransitSign(labels: ["train station"], recognizedText: []))
    }

    @Test func `A stop code on the sign passes`() {
        #expect(TransitSignGate.looksLikeTransitSign(labels: ["sign"], recognizedText: ["Stop #75403"]))
    }

    @Test func `A transit word on the sign passes`() {
        #expect(TransitSignGate.looksLikeTransitSign(labels: [], recognizedText: ["King County METRO"]))
    }

    @Test func `An unrelated search does not pass`() {
        #expect(!TransitSignGate.looksLikeTransitSign(labels: ["dog", "pet"], recognizedText: ["Good boy"]))
        #expect(!TransitSignGate.looksLikeTransitSign(labels: [], recognizedText: []))
    }

    /// A traffic stop sign and a highway's route number are not transit signs.
    @Test func `Stop and route alone do not pass`() {
        #expect(!TransitSignGate.looksLikeTransitSign(labels: ["sign"], recognizedText: ["STOP"]))
        #expect(!TransitSignGate.looksLikeTransitSign(labels: [], recognizedText: ["Route 99"]))
    }

    /// Prices and route numbers are too short for a stop code; a phone number is too long.
    @Test func `Only three to eight digit numbers look like stop codes`() {
        #expect(!TransitSignGate.isPlausibleStopCode("72"))
        #expect(TransitSignGate.isPlausibleStopCode("994"))
        #expect(TransitSignGate.isPlausibleStopCode("75403"))
        #expect(!TransitSignGate.isPlausibleStopCode("2065551234"))
        #expect(!TransitSignGate.isPlausibleStopCode("E3A"))
    }
}
