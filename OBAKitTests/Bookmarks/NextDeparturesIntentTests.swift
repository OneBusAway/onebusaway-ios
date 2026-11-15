//
//  NextDeparturesIntentTests.swift
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

@Suite(.serialized)
final class NextDeparturesIntentTests: OBATestCase {

    override init() async throws {
        try await super.init()
        ResolvedRegionStore(userDefaults: userDefaults).write(Fixtures.pugetSoundRegion)
    }

    private func loader(dataLoader: MockDataLoader? = nil) -> NextDeparturesLoader {
        let dl = dataLoader ?? MockDataLoader(testName: name)
        return NextDeparturesLoader(
            userDefaults: userDefaults,
            bundledRegionsFilePath: nil,
            apiKey: apiKey,
            appVersion: appVersion,
            dataLoader: dl
        )
    }

    // MARK: - Empty

    @Test func `Candidate resolution with 0 candidates returns nil`() throws {
        let intent = NextDeparturesIntent()
        let resolved = try intent.resolveBookmarkID(candidates: [])
        #expect(resolved == nil)
    }

    // MARK: - Exact

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
        let intent = NextDeparturesIntent(bookmark: explicit)

        let candidateID = UUID()
        let candidate = BookmarkEntity(id: candidateID, name: "Other Bookmark")

        #expect(try intent.resolveBookmarkID(candidates: []) == explicitID)
        #expect(try intent.resolveBookmarkID(candidates: [candidate]) == explicitID)
        #expect(try intent.resolveBookmarkID(candidates: [candidate, explicit]) == explicitID)
    }

    // MARK: - Duplicate / Ambiguity

    @Test func `Candidate resolution with multiple candidates throws needsValueError prompting which bookmark`() {
        let intent = NextDeparturesIntent()
        let candidate1 = BookmarkEntity(id: UUID(), name: "49 to Downtown")
        let candidate2 = BookmarkEntity(id: UUID(), name: "8 to Seattle Center")

        #expect(throws: (any Error).self) {
            try intent.resolveBookmarkID(candidates: [candidate1, candidate2])
        }

        do {
            _ = try intent.resolveBookmarkID(candidates: [candidate1, candidate2])
            Issue.record("Expected needsValueError to be thrown for multiple candidates")
        } catch {
            #expect("\(type(of: error))" == "AppIntentError" || "\(error)".localizedCaseInsensitiveContains("missing parameter"))
        }
    }

    // MARK: - Deleted Bookmark & Deleted Stop

    @Test func `Deleted bookmark returns bookmarkUnavailable and never chooses wrong stop`() async throws {
        let deletedUUID = UUID()
        let outcome = await loader().outcome(bookmarkID: deletedUUID)
        #expect(outcome == .bookmarkUnavailable)
    }

    @Test func `Deleted stop in different region returns stopUnavailable`() async throws {
        let otherRegionEntityID = StopEntityMapping.identifier(
            regionID: Fixtures.pugetSoundRegion.regionIdentifier + 99,
            stopID: "99_99999"
        )
        let outcome = await loader().outcome(stopEntityID: otherRegionEntityID)
        #expect(outcome == .stopUnavailable)
    }

    @Test func `Deleted stop in current region resolves to fallback entity with its stop ID`() {
        let stopID = "1_99999"
        let stopEntityID = StopEntityMapping.identifier(
            regionID: Fixtures.pugetSoundRegion.regionIdentifier,
            stopID: stopID
        )

        let entities = StopEntityMapping.entities(
            forIdentifiers: [stopEntityID],
            bookmarks: [],
            recentStops: []
        )
        #expect(entities.count == 1)

        let fallback = try? #require(entities.first)
        #expect(fallback?.id == stopEntityID)
        #expect(fallback?.name == nil)
        #expect(fallback?.stopID == stopID)
        #expect(fallback?.regionID == Fixtures.pugetSoundRegion.regionIdentifier)
        #expect(fallback?.destination == AppLinksRouter.StopDestination(stopID: stopID, regionID: Fixtures.pugetSoundRegion.regionIdentifier))
        #expect(fallback?.title == "Stop \(stopID)")
    }
}
