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
/// Pure data so the flow computation is synchronous and unit-testable; the async
/// gathering (notification settings) happens once in `current(application:)`.
public struct OnboardingEnvironment: Sendable {
    public var hasDataToMigrate: Bool
    public var shouldPerformMigration: Bool
    public var hasCurrentRegion: Bool
    public var locationAuthorizationDetermined: Bool
    public var notificationAuthorizationDetermined: Bool
    public var isPushServiceConfigured: Bool

    public init(
        hasDataToMigrate: Bool,
        shouldPerformMigration: Bool,
        hasCurrentRegion: Bool,
        locationAuthorizationDetermined: Bool,
        notificationAuthorizationDetermined: Bool,
        isPushServiceConfigured: Bool
    ) {
        self.hasDataToMigrate = hasDataToMigrate
        self.shouldPerformMigration = shouldPerformMigration
        self.hasCurrentRegion = hasCurrentRegion
        self.locationAuthorizationDetermined = locationAuthorizationDetermined
        self.notificationAuthorizationDetermined = notificationAuthorizationDetermined
        self.isPushServiceConfigured = isPushServiceConfigured
    }

    @MainActor
    public static func current(application: Application) async -> OnboardingEnvironment {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return OnboardingEnvironment(
            hasDataToMigrate: application.hasDataToMigrate,
            shouldPerformMigration: application.shouldPerformMigration,
            hasCurrentRegion: application.regionsService.currentRegion != nil,
            locationAuthorizationDetermined: application.locationService.authorizationStatus != .notDetermined,
            notificationAuthorizationDetermined: settings.authorizationStatus != .notDetermined,
            isPushServiceConfigured: application.pushService != nil)
    }
}

/// One entry in the onboarding registry.
public struct OnboardingStep: Identifiable, Sendable {
    public let id: OnboardingStepID
    /// Sort key. Lower weights show earlier. Leave gaps so future steps can slot in.
    public let weight: Int
    /// Bump to re-show a changed step to everyone who saw an older version.
    public let version: Int
    /// When false, the seen-store is ignored and `isEligible` alone governs
    /// re-prompting (used by migration, which re-prompts until it succeeds).
    public let tracksSeen: Bool
    public let isEligible: @Sendable (OnboardingEnvironment) -> Bool

    public init(id: OnboardingStepID, weight: Int, version: Int, tracksSeen: Bool = true, isEligible: @escaping @Sendable (OnboardingEnvironment) -> Bool) {
        self.id = id
        self.weight = weight
        self.version = version
        self.tracksSeen = tracksSeen
        self.isEligible = isEligible
    }
}
