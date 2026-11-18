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
        var intent = NextDeparturesIntent()
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
}
