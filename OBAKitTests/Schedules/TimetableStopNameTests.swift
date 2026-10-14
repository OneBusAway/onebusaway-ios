//
//  TimetableStopNameTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
@testable import OBAKit

@Suite(.serialized)
struct TimetableStopNameTests {
    @Test func `Intersection splits into street and cross street`() {
        let name = TimetableStopName("Sand Point Way NE & NE 74th St")
        #expect(name.street == "Sand Point Way NE &")
        #expect(name.crossStreet == "NE 74th St")
    }

    @Test func `Only the first ampersand splits`() {
        let name = TimetableStopName("A St & B St & C St")
        #expect(name.street == "A St &")
        #expect(name.crossStreet == "B St & C St")
    }

    @Test func `Non-intersection name is kept whole`() {
        let name = TimetableStopName("Northgate Station - Bay 1")
        #expect(name.street == nil)
        #expect(name.crossStreet == "Northgate Station - Bay 1")
    }

    @Test func `Ampersand without surrounding spaces is not split`() {
        let name = TimetableStopName("A&B Market")
        #expect(name.street == nil)
        #expect(name.crossStreet == "A&B Market")
    }

    @Test func `Empty side keeps the name whole`() {
        let name = TimetableStopName(" & NE 74th St")
        #expect(name.street == nil)
        #expect(name.crossStreet == " & NE 74th St")
    }
}
