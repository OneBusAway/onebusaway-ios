//
//  NextDeparturesIntentTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite
struct NextDeparturesIntentTests {

    // MARK: - Candidate Resolution

    @Test func `Candidate resolution with 0 candidates returns nil`() throws {
        let intent = NextDeparturesIntent()
        let resolved = try intent.resolveBookmarkID(candidates: [])
        #expect(resolved == nil)
    }

    @Test func `Candidate resolution with single candidate returns candidate id`() throws {
        let intent = NextDeparturesIntent()
        let candidateID = UUID()
        let candidate = BookmarkEntity(id: candidateID, name: "49 to Downtown")

        let resolved = try intent.resolveBookmarkID(candidates: [candidate])
        #expect(resolved == candidateID)
    }

    @Test func `Candidate resolution with explicit bookmark parameter returns explicit id`() throws {
        let explicitID = UUID()
        let explicit = BookmarkEntity(id: explicitID, name: "Explicit Bookmark")
        let intent = NextDeparturesIntent()
        intent.bookmark = explicit

        let candidateID = UUID()
        let candidate = BookmarkEntity(id: candidateID, name: "Other Bookmark")

        #expect(try intent.resolveBookmarkID(candidates: []) == explicitID)
        #expect(try intent.resolveBookmarkID(candidates: [candidate]) == explicitID)
        #expect(try intent.resolveBookmarkID(candidates: [candidate, explicit]) == explicitID)
    }

    @Test func `Candidate resolution with multiple candidates throws needsValueError prompting which bookmark`() {
        let intent = NextDeparturesIntent()
        let candidate1 = BookmarkEntity(id: UUID(), name: "49 to Downtown")
        let candidate2 = BookmarkEntity(id: UUID(), name: "8 to Seattle Center")

        #expect(throws: (any Error).self) {
            try intent.resolveBookmarkID(candidates: [candidate1, candidate2])
        }
    }

    @Suite
    final class QueryResolutionTests: OBATestCase {

        override init() async throws {
            try await super.init()
        }

        private func makeQuery() -> BookmarkEntityQuery {
            let suite = userDefaultsSuiteName
            return BookmarkEntityQuery { UserDefaults(suiteName: suite) }
        }

        private func makeStop(id: StopID, regionID: Int) -> Stop {
            Stop(
                id: id,
                name: "Stop \(id)",
                location: CLLocation(latitude: 47.6097, longitude: -122.3422),
                regionIdentifier: regionID
            )
        }

        private func makeTripBookmark(name: String, stop: Stop, regionID: Int) throws -> Bookmark {
            let stopArrivals = try Fixtures.loadRESTAPIPayload(
                type: StopArrivals.self,
                fileName: "arrivals-and-departures-for-stop-1_10914.json"
            )
            let arrivalDeparture = try #require(stopArrivals.arrivalsAndDepartures.first)
            return Bookmark(name: name, regionIdentifier: regionID, arrivalDeparture: arrivalDeparture, stop: stop)
        }

        @Test func `End-to-end resolution with nil UserDefaults or missing region returns nil`() async throws {
            let intent = NextDeparturesIntent()
            #expect(try await intent.resolveBookmarkID(using: BookmarkEntityQuery { nil }) == nil)

            let store = UserDefaultsStore(userDefaults: userDefaults)
            store.add(try makeTripBookmark(name: "49 to Downtown", stop: makeStop(id: "1_100", regionID: 1), regionID: 1))
            userDefaults.removeObject(forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)

            #expect(try await intent.resolveBookmarkID(using: makeQuery()) == nil)
        }

        @Test func `End-to-end resolution ignores whole-stop and out-of-region bookmarks when resolving single candidate`() async throws {
            userDefaults.set(1, forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)
            let store = UserDefaultsStore(userDefaults: userDefaults)

            let stopCurrent = makeStop(id: "1_100", regionID: 1)
            let stopOther = makeStop(id: "2_200", regionID: 2)
            let wholeStop = Bookmark(name: "Whole Stop", regionIdentifier: 1, stop: stopCurrent)
            let otherRegionTrip = try makeTripBookmark(name: "52 to Centrum", stop: stopOther, regionID: 2)

            store.bookmarks = [wholeStop, otherRegionTrip]

            let intent = NextDeparturesIntent()
            #expect(try await intent.resolveBookmarkID(using: makeQuery()) == nil)

            let currentTrip = try makeTripBookmark(name: "49 to Downtown", stop: stopCurrent, regionID: 1)
            store.add(currentTrip)

            #expect(try await intent.resolveBookmarkID(using: makeQuery()) == currentTrip.id)
        }

        @Test func `End-to-end resolution with multiple current-region trip bookmarks throws unless explicit parameter set`() async throws {
            userDefaults.set(1, forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)
            let store = UserDefaultsStore(userDefaults: userDefaults)
            let stop = makeStop(id: "1_100", regionID: 1)

            let first = try makeTripBookmark(name: "49 to Downtown", stop: stop, regionID: 1)
            let second = try makeTripBookmark(name: "8 to Seattle Center", stop: stop, regionID: 1)
            store.bookmarks = [first, second]

            let query = makeQuery()
            await #expect(throws: (any Error).self) {
                _ = try await NextDeparturesIntent().resolveBookmarkID(using: query)
            }

            let explicitIntent = NextDeparturesIntent()
            explicitIntent.bookmark = BookmarkEntity(id: second.id, name: second.name)
            #expect(try await explicitIntent.resolveBookmarkID(using: query) == second.id)
        }
    }
}
