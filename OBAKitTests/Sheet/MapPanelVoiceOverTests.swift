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

    private let collapsed = AppSheetRoute.homeCollapsedDetent

    @Test func `VoiceOver raises the collapsed home sheet`() {
        #expect(MapPanelVoiceOver.homeDetent(isVoiceOverRunning: true, expandsSheet: true, currentDetent: collapsed, isCovered: false) == .medium)
    }

    @Test func `The setting, VoiceOver off, or a sheet already moved leaves it alone`() {
        #expect(MapPanelVoiceOver.homeDetent(isVoiceOverRunning: true, expandsSheet: false, currentDetent: collapsed, isCovered: false) == nil)
        #expect(MapPanelVoiceOver.homeDetent(isVoiceOverRunning: false, expandsSheet: true, currentDetent: collapsed, isCovered: false) == nil)
        #expect(MapPanelVoiceOver.homeDetent(isVoiceOverRunning: true, expandsSheet: true, currentDetent: AppSheetRoute.largeDetent, isCovered: false) == nil)
    }

    /// #1623 follow-up: turning VoiceOver on with a stop open resized the home
    /// sheet hidden underneath it.
    @Test func `A home sheet under a stacked sheet stays where it is`() {
        #expect(MapPanelVoiceOver.homeDetent(isVoiceOverRunning: true, expandsSheet: true, currentDetent: collapsed, isCovered: true) == nil)
    }
}
