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
    func `English line cue searches by route`() {
        let request = VoiceSearchQueryClassifier.request(from: "line 40")

        #expect(request.searchType == .route)
        #expect(request.query == "40")
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

    @Test(arguments: [
        ("ruta 40", "40"),          // es
        ("Autobús 8", "8"),         // es
        ("linha 509", "509"),       // pt-BR
        ("ônibus 8", "8"),          // pt-BR
        ("autobus 64", "64"),       // it
        ("tuyến 32", "32"),         // vi
        ("خط 7", "7"),              // ar
        ("linya 4", "4"),           // fil
        ("버스 720", "720")          // ko
    ])
    func `Locale route cues search by route`(utterance: String, query: String) {
        let request = VoiceSearchQueryClassifier.request(from: utterance)

        #expect(request.searchType == .route)
        #expect(request.query == query)
    }

    @Test
    func `Multi-word cue wins over its shorter prefix`() {
        // "tuyến" alone would leave "xe buýt 32" as the query.
        let request = VoiceSearchQueryClassifier.request(from: "tuyến xe buýt 32")

        #expect(request.searchType == .route)
        #expect(request.query == "32")
    }

    @Test(arguments: [
        ("veículo 4351", "4351"),   // pt-BR
        ("veicolo 4351", "4351"),   // it
        ("phương tiện 4351", "4351"), // vi
        ("مركبة 4351", "4351"),     // ar
        ("sasakyan 4351", "4351")   // fil
    ])
    func `Locale vehicle cues search by vehicle ID`(utterance: String, query: String) {
        let request = VoiceSearchQueryClassifier.request(from: utterance)

        #expect(request.searchType == .vehicleID)
        #expect(request.query == query)
    }

    @Test
    func `Rutabaga is not treated as a ruta cue`() {
        let request = VoiceSearchQueryClassifier.request(from: "rutabaga farm")

        #expect(request.searchType == .address)
    }
}
