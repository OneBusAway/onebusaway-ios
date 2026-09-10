//
//  TipsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import SwiftUI
import Testing
import TipKit
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
@MainActor
final class TipsTests {
    
    @Test func `ScheduleTip provides correct properties`() {
        let tip = ScheduleTip()
        
        #expect(tip.title == Text(Strings.scheduleTipTitle))
        #expect(tip.message == Text(Strings.scheduleTipMessage))
        #expect(tip.image == Image(systemName: "calendar"))
    }

    @Test func `TripPlannerTip provides correct properties`() {
        let tip = TripPlannerTip()
        
        #expect(tip.title == Text(Strings.tripPlannerTipTitle))
        #expect(tip.message == Text(Strings.tripPlannerTipMessage))
        #expect(tip.image == Image(systemName: "map.fill"))
    }

    @Test func `MapLayersTip provides correct properties and ignores frequency budget`() {
        let tip = MapLayersTip()
        
        #expect(tip.title == Text(Strings.mapLayersTipTitle))
        #expect(tip.message == Text(Strings.mapLayersTipMessage))
        #expect(tip.image == Image(systemName: "bicycle"))
        
        let options = tip.options
        
        // Find and assert the specific option types and their configured values
        let maxDisplayCount = options.compactMap { $0 as? Tips.MaxDisplayCount }.first
        let ignoresFrequency = options.compactMap { $0 as? Tips.IgnoresDisplayFrequency }.first
        
        #expect(maxDisplayCount != nil, "Missing MaxDisplayCount option")
        // Note: MaxDisplayCount's value is tested via its textual representation since its internal value is opaque/not easily equatable in some Swift versions, but it conforms to CustomStringConvertible or similar.
        #expect(String(describing: maxDisplayCount).contains("1"))
        
        #expect(ignoresFrequency != nil, "Missing IgnoresDisplayFrequency option")
        #expect(String(describing: ignoresFrequency).contains("true"))
    }
}
