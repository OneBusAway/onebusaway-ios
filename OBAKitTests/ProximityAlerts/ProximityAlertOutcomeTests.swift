//
//  ProximityAlertOutcomeTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
import UserNotifications
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try

/// The Stop page's proximity-alert decisions, tested where they are reachable.
///
/// The presenter that acts on them cannot reach most of these states in a test:
/// the flow's first step reads the device's real location and notification
/// authorization, which on a test runner is a fresh, undetermined install, and
/// driving it past that point would raise system prompts. So the decisions live
/// here instead of in the presenter, and are covered case by case — a seventh
/// activation result or a sixth authorization step fails to compile rather than
/// falling through a `default`.
///
/// What the presenter *can* be tested on — that each reason presents its own
/// alert — is in `StopPageActionPresenterTests`.
@Suite(.serialized)
final class ProximityAlertOutcomeTests: OBATestCase {

    private var stops: [Stop]!

    override init() async throws {
        try await super.init()
        stops = try! Fixtures.loadSomeStops()
    }

    /// Which stop is irrelevant here — the reducer never reads one — but the
    /// alert has to be a real `ProximityAlert` so `.cancel` carries the same
    /// identity the presenter would hand the manager.
    private func makeAlert() -> ProximityAlert {
        ProximityAlert(stop: stops[0])
    }

    // MARK: - An existing alert wins

    @Test func `An existing alert cancels regardless of the step`() {
        let alert = makeAlert()
        let steps: [ProximityAlertAuthorizationStep] = [
            .ready,
            .promptForLocation,
            .promptForNotifications,
            .locationBlocked(.denied),
            .notificationsBlocked
        ]

        for step in steps {
            #expect(
                ProximityAlertOutcome.action(forStep: step, existing: alert) == .cancel(alert),
                "\(step) should still cancel the alert the rider already has"
            )
        }
    }

    // MARK: - Steps

    @Test func `Ready arms`() {
        #expect(ProximityAlertOutcome.action(forStep: .ready, existing: nil) == .arm)
    }

    @Test func `A promptable location status asks, and never arms`() {
        #expect(ProximityAlertOutcome.action(forStep: .promptForLocation, existing: nil) == .requestLocation)
    }

    @Test func `A promptable notification status asks`() {
        #expect(ProximityAlertOutcome.action(forStep: .promptForNotifications, existing: nil) == .requestNotifications)
    }

    @Test func `Blocked notifications route to the notifications guidance`() {
        #expect(ProximityAlertOutcome.action(forStep: .notificationsBlocked, existing: nil) == .showSettings(.notifications))
    }

    // MARK: - The blocked location status is used, not dropped

    @Test func `When In Use asks the rider to widen to Always`() {
        #expect(
            ProximityAlertOutcome.action(forStep: .locationBlocked(.authorizedWhenInUse), existing: nil)
                == .showSettings(.locationWhenInUse)
        )
    }

    @Test func `Denied location says location is off`() {
        #expect(
            ProximityAlertOutcome.action(forStep: .locationBlocked(.denied), existing: nil)
                == .showSettings(.locationDenied)
        )
    }

    @Test func `Restricted location promises nothing`() {
        #expect(
            ProximityAlertOutcome.action(forStep: .locationBlocked(.restricted), existing: nil)
                == .showSettings(.locationRestricted)
        )
    }

    @Test func `The three blocked location statuses give three different reasons`() {
        // The whole point of `.locationBlocked` carrying a status: collapsing
        // these would put the wrong instruction in front of two riders in three.
        let reasons = Set([
            ProximityAlertOutcome.action(forStep: .locationBlocked(.authorizedWhenInUse), existing: nil),
            ProximityAlertOutcome.action(forStep: .locationBlocked(.denied), existing: nil),
            ProximityAlertOutcome.action(forStep: .locationBlocked(.restricted), existing: nil)
        ].map { "\($0)" })
        #expect(reasons.count == 3)
    }

    @Test func `A spent prompt on an undetermined status reads as denied`() {
        // Reachable when the one-time prompt is spent but the status never moved
        // — a missing usage description, or an "Allow Once" answer. Nothing has
        // been granted, so the denied copy is the accurate one.
        #expect(
            ProximityAlertOutcome.action(forStep: .locationBlocked(.notDetermined), existing: nil)
                == .showSettings(.locationDenied)
        )
    }

    // MARK: - Results

    @Test func `An activated alert confirms`() {
        #expect(ProximityAlertOutcome.action(forResult: .activated(makeAlert())) == .confirmActivated)
    }

    @Test func `A clamped radius is still a success`() {
        // The rider chose no radius, so there is nothing to tell them about — but
        // the alert did arm, and silence here would look like a failed tap.
        let result = ProximityAlertActivationResult.activatedWithClampedRadius(makeAlert(), requested: 10_000, monitored: 400)
        #expect(ProximityAlertOutcome.action(forResult: result) == .confirmActivated)
    }

    @Test func `An already-active alert refreshes without confirming`() {
        #expect(ProximityAlertOutcome.action(forResult: .alreadyActive(makeAlert())) == .refresh)
    }

    @Test func `Missing location authorization re-resolves rather than guessing`() {
        #expect(ProximityAlertOutcome.action(forResult: .needsLocationAuthorization(.authorizedWhenInUse)) == .resolveAgain)
    }

    @Test func `Missing notification authorization re-resolves rather than guessing`() {
        #expect(ProximityAlertOutcome.action(forResult: .needsNotificationAuthorization(.denied)) == .resolveAgain)
    }

    @Test func `The region limit survives into the action`() {
        // The number is what the alert's copy names, so dropping it would leave
        // the rider told to cancel one of an unstated many.
        #expect(ProximityAlertOutcome.action(forResult: .regionLimitReached(limit: 20)) == .showLimit(20))
    }
}
