//
//  MapPanelPromptsTests.swift
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

/// The feedback prompt's only call site was the UIKit map, so riders on the
/// panel were never asked. The panel asks where the UIKit map does: back on the
/// map, a beat after a stop sheet closes.
@Suite
struct MapPanelPromptsTests {

    private let stop = AppSheetRoute.stopDetails(stopID: "1_75403")

    @Test func `Closing a stop sheet back to the map ends a stop visit`() {
        #expect(MapPanelPrompts.endsStopVisit(previous: [stop], current: []))
        #expect(MapPanelPrompts.endsStopVisit(previous: [.nearbyAll, stop], current: []))
    }

    @Test func `Anything still open, or no stop closed, is not a stopping point`() {
        #expect(!MapPanelPrompts.endsStopVisit(previous: [.nearbyAll, stop], current: [.nearbyAll]))
        #expect(!MapPanelPrompts.endsStopVisit(previous: [.more], current: []))
        #expect(!MapPanelPrompts.endsStopVisit(previous: [], current: [stop]))
    }
}
