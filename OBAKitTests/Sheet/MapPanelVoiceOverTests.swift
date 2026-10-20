//
//  MapPanelVoiceOverTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import Testing
@testable import OBAKit

/// A VoiceOver rider used to land on a home sheet holding only a search field.
@Suite
struct MapPanelVoiceOverTests {

    private let collapsed = PresentationDetent.height(AppSheetRoute.homeCollapsedHeight)

    @Test func `VoiceOver raises the collapsed home sheet`() {
        #expect(MapPanelVoiceOver.homeDetent(isVoiceOverRunning: true, expandsSheet: true, currentDetent: collapsed) == .medium)
    }

    @Test func `The setting, VoiceOver off, or a sheet already moved leaves it alone`() {
        #expect(MapPanelVoiceOver.homeDetent(isVoiceOverRunning: true, expandsSheet: false, currentDetent: collapsed) == nil)
        #expect(MapPanelVoiceOver.homeDetent(isVoiceOverRunning: false, expandsSheet: true, currentDetent: collapsed) == nil)
        #expect(MapPanelVoiceOver.homeDetent(isVoiceOverRunning: true, expandsSheet: true, currentDetent: AppSheetRoute.largeDetent) == nil)
    }
}
