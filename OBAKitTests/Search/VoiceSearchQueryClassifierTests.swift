//
//  VoiceSearchQueryClassifierTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
@testable import OBAKit

/// Pure mapping from a spoken utterance to a `SearchRequest`.
@Suite(.serialized)
struct VoiceSearchQueryClassifierTests {

    @Test
    func `Mostly digits become a stop-number search`() {
        let request = VoiceSearchQueryClassifier.request(from: "  1234  ")

        #expect(request.searchType == .stopNumber)
        #expect(request.query == "1234")
    }

    @Test
    func `Stop IDs with underscores stay stop-number searches`() {
        let request = VoiceSearchQueryClassifier.request(from: "1_390")

        #expect(request.searchType == .stopNumber)
        #expect(request.query == "1_390")
    }

    @Test
    func `Route cue strips the cue and searches by route`() {
        let request = VoiceSearchQueryClassifier.request(from: "route 40")

        #expect(request.searchType == .route)
        #expect(request.query == "40")
    }

    @Test
    func `Bus cue searches by route`() {
        let request = VoiceSearchQueryClassifier.request(from: "bus 8")

        #expect(request.searchType == .route)
        #expect(request.query == "8")
    }

    @Test
    func `Vehicle cue searches by vehicle ID`() {
        let request = VoiceSearchQueryClassifier.request(from: "vehicle 4351")

        #expect(request.searchType == .vehicleID)
        #expect(request.query == "4351")
    }

    @Test
    func `Plain place names default to address search`() {
        let request = VoiceSearchQueryClassifier.request(from: "Pike Place Market")

        #expect(request.searchType == .address)
        #expect(request.query == "Pike Place Market")
    }

    @Test
    func `Whitespace-only utterances stay empty address searches`() {
        let request = VoiceSearchQueryClassifier.request(from: "   ")

        #expect(request.searchType == .address)
        #expect(request.query.isEmpty)
    }

    @Test
    func `Route cue preserves remainder case`() {
        let request = VoiceSearchQueryClassifier.request(from: "Route Rapid Ride D")

        #expect(request.searchType == .route)
        #expect(request.query == "Rapid Ride D")
    }

    @Test
    func `Route cue with punctuation strips the separator`() {
        let request = VoiceSearchQueryClassifier.request(from: "route: 40")

        #expect(request.searchType == .route)
        #expect(request.query == "40")
    }

    @Test
    func `Business is not treated as a bus cue`() {
        let request = VoiceSearchQueryClassifier.request(from: "business district")

        #expect(request.searchType == .address)
        #expect(request.query == "business district")
    }
}
