//
//  OBAFloatingPanelControllerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import FloatingPanel
import Foundation
import Testing
@testable import OBAKit

/// The grabber's Expand and Collapse actions are how VoiceOver and Switch Control
/// users resize a card. They stepped through `layout.anchors` — a dictionary —
/// by index, so the next position was arbitrary and Collapse trapped outright.
@MainActor
@Suite(.serialized)
struct OBAFloatingPanelControllerTests {

    private typealias Target = OBAFloatingPanelController

    /// Shuffled on purpose: the order anchors arrive in must not matter.
    private let anchors: [FloatingPanelState] = [.half, .full, .hidden, .tip]

    @Test func `Expand steps up one position`() {
        #expect(Target.accessibilityTargetState(from: .tip, among: anchors, direction: .expand) == .half)
        #expect(Target.accessibilityTargetState(from: .half, among: anchors, direction: .expand) == .full)
    }

    @Test func `Collapse steps down one position`() {
        #expect(Target.accessibilityTargetState(from: .full, among: anchors, direction: .collapse) == .half)
        #expect(Target.accessibilityTargetState(from: .half, among: anchors, direction: .collapse) == .tip)
    }

    @Test func `There is nothing past either end`() {
        #expect(Target.accessibilityTargetState(from: .full, among: anchors, direction: .expand) == nil)
        #expect(Target.accessibilityTargetState(from: .tip, among: anchors, direction: .collapse) == nil)
    }

    /// Collapsing into `.hidden` would take the grabber with it, and with it the
    /// only way back.
    @Test func `Collapse never hides the card`() {
        #expect(Target.accessibilityTargetState(from: .tip, among: [.hidden, .tip, .full], direction: .collapse) == nil)
    }

    @Test func `Only the layout's own anchors are targets`() {
        #expect(Target.accessibilityTargetState(from: .tip, among: [.tip, .full], direction: .expand) == .full)
        #expect(Target.accessibilityTargetState(from: .half, among: [.tip, .full], direction: .expand) == nil)
    }

    /// Starting a trip shrinks the planner to `.tip` to show the route map, which
    /// under VoiceOver leaves the itinerary unreadable for a map that says nothing.
    @Test func `Starting a trip keeps the planner readable under VoiceOver`() {
        #expect(MapViewController.tripStartedPanelState(isVoiceOverRunning: true) == .half)
        #expect(MapViewController.tripStartedPanelState(isVoiceOverRunning: false) == .tip)
    }
}
