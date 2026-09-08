//
//  ProximityAlertAuthorizationTests.swift
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

@Suite(.serialized)
final class ProximityAlertAuthorizationTests: OBATestCase {

    private func step(
        location: CLAuthorizationStatus,
        canPromptForAlways: Bool = true,
        notifications: UNAuthorizationStatus = .authorized
    ) -> ProximityAlertAuthorizationStep {
        ProximityAlertAuthorizationStep.resolve(
            locationStatus: location,
            canPromptForAlways: canPromptForAlways,
            notificationStatus: notifications
        )
    }

    // MARK: - Nothing missing

    @Test func `Always plus authorized notifications is ready`() {
        #expect(step(location: .authorizedAlways, notifications: .authorized) == .ready)
    }

    @Test func `Provisional notifications are enough`() {
        // Quiet delivery is a poor fit for an alert meant to interrupt someone
        // watching the road, but it is still delivery — and `createProximityAlert`
        // accepts it, so refusing here would disagree with the code that acts.
        #expect(step(location: .authorizedAlways, notifications: .provisional) == .ready)
    }

    @Test func `Ephemeral notifications are enough`() {
        #expect(step(location: .authorizedAlways, notifications: .ephemeral) == .ready)
    }

    @Test func `A spent Always prompt is irrelevant once Always is granted`() {
        // The one-shot only gates *asking*. Having spent it says nothing about a
        // rider who has already granted what was asked for.
        #expect(step(location: .authorizedAlways, canPromptForAlways: false) == .ready)
    }

    // MARK: - Location can still be asked for

    @Test func `Undetermined location can be prompted for`() {
        #expect(step(location: .notDetermined) == .promptForLocation)
    }

    @Test func `When In Use can be upgraded while the prompt is unspent`() {
        #expect(step(location: .authorizedWhenInUse) == .promptForLocation)
    }

    // MARK: - Location cannot be asked for

    @Test func `When In Use is blocked once the prompt is spent`() {
        // The status is identical either side of the one-time upgrade prompt, so
        // without the flag this case is indistinguishable from the one above —
        // and the UI would ask forever, raising nothing.
        #expect(step(location: .authorizedWhenInUse, canPromptForAlways: false) == .locationBlocked(.authorizedWhenInUse))
    }

    @Test func `Undetermined location is blocked once the prompt is spent`() {
        #expect(step(location: .notDetermined, canPromptForAlways: false) == .locationBlocked(.notDetermined))
    }

    @Test func `Denied location is blocked even with the prompt unspent`() {
        // iOS raises nothing from `.denied`, however much prompt budget is left.
        #expect(step(location: .denied) == .locationBlocked(.denied))
    }

    @Test func `Restricted location is blocked`() {
        // Carried through rather than folded into `.denied`: a restriction may be
        // device policy the rider cannot lift, so the copy differs.
        #expect(step(location: .restricted) == .locationBlocked(.restricted))
    }

    // MARK: - Notifications

    @Test func `Undetermined notifications are prompted for after location is settled`() {
        #expect(step(location: .authorizedAlways, notifications: .notDetermined) == .promptForNotifications)
    }

    @Test func `Denied notifications are blocked`() {
        #expect(step(location: .authorizedAlways, notifications: .denied) == .notificationsBlocked)
    }

    // MARK: - Ordering

    @Test func `Location is resolved before notifications`() {
        // Both are missing. Location has to win: a rider who will not grant
        // background location cannot use this feature at all, and iOS gives the
        // notification prompt one appearance per install — spending it here would
        // burn it on a feature already dead, in a context that explains nothing.
        #expect(step(location: .notDetermined, notifications: .notDetermined) == .promptForLocation)
    }

    @Test func `Blocked location outranks blocked notifications`() {
        #expect(step(location: .denied, notifications: .denied) == .locationBlocked(.denied))
    }

    @Test func `Blocked location outranks perfectly good notifications`() {
        #expect(step(location: .denied, notifications: .authorized) == .locationBlocked(.denied))
    }
}
