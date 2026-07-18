//
//  OnboardingStep.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import UserNotifications

/// A snapshot of the app state that onboarding eligibility predicates run against.
/// Pure data so the flow computation is synchronous and unit-testable; any async
/// gathering (the notification-settings fetch, when a push provider exists) happens
/// up front in `current(application:)`.
struct OnboardingEnvironment: Sendable {
    var hasDataToMigrate: Bool
    var shouldPerformMigration: Bool
    var locationAuthorizationDetermined: Bool
    var notificationAuthorizationDetermined: Bool
    var isPushServiceConfigured: Bool

    @MainActor
    static func current(application: Application) async -> OnboardingEnvironment {
        // The notification-settings fetch is an XPC round trip on the launch path;
        // skip it when no push provider exists — the notifications predicate is
        // false regardless, so the answer can't matter.
        let isPushServiceConfigured = application.pushService != nil
        let notificationAuthorizationDetermined: Bool
        if isPushServiceConfigured {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationAuthorizationDetermined = settings.authorizationStatus != .notDetermined
        } else {
            notificationAuthorizationDetermined = false
        }

        return OnboardingEnvironment(
            hasDataToMigrate: application.hasDataToMigrate,
            shouldPerformMigration: application.shouldPerformMigration,
            locationAuthorizationDetermined: !application.locationService.canRequestAuthorization,
            notificationAuthorizationDetermined: notificationAuthorizationDetermined,
            isPushServiceConfigured: isPushServiceConfigured)
    }
}

/// One entry in the onboarding registry.
struct OnboardingStep: Identifiable, Sendable {
    let id: OnboardingStepID
    /// Sort key. Lower weights show earlier. Leave gaps so future steps can slot in.
    let weight: Int
    /// Bump to re-show a changed step to everyone who saw an older version.
    let version: Int
    /// When false, the seen-store is ignored and `isEligible` alone governs
    /// re-prompting (used by migration, which re-prompts until it succeeds).
    let tracksSeen: Bool
    let isEligible: @Sendable (OnboardingEnvironment) -> Bool

    init(id: OnboardingStepID, weight: Int, version: Int, tracksSeen: Bool = true, isEligible: @escaping @Sendable (OnboardingEnvironment) -> Bool) {
        // seenVersion defaults to 0, so a version below 1 could never exceed it and
        // would silently disable the step forever.
        precondition(version >= 1, "OnboardingStep.version must be >= 1")
        self.id = id
        self.weight = weight
        self.version = version
        self.tracksSeen = tracksSeen
        self.isEligible = isEligible
    }
}
