//
//  TipsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import TipKit
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
@MainActor
final class TipsTests {
    
    @Test func `ScheduleTip provides correct properties`() {
        let tip = ScheduleTip()
        
        #expect(tip.title != nil)
        #expect(tip.message != nil)
        #expect(tip.image != nil)
    }

    @Test func `TripPlannerTip provides correct properties`() {
        let tip = TripPlannerTip()
        
        #expect(tip.title != nil)
        #expect(tip.message != nil)
        #expect(tip.image != nil)
    }

    @Test func `MapLayersTip provides correct properties and ignores frequency budget`() {
        let tip = MapLayersTip()
        
        #expect(tip.title != nil)
        #expect(tip.message != nil)
        #expect(tip.image != nil)
        
        // MapLayersTip should have options configured to ignore display frequency and set max count
        let options = tip.options
        #expect(options.count == 2)
    }
}
