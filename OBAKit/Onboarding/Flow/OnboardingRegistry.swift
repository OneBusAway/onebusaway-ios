//
//  OnboardingRegistry.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// The ordered registry of onboarding steps. The flow shown to a user is this list
/// filtered by eligibility and what they haven't seen yet, sorted by weight.
///
/// To add a step: add a case to `OnboardingStepID` (its raw value is the persistence
/// key), append an entry here, and add a matching case to `OnboardingFlowView`'s step
/// switch. Existing users will see the new step by itself on their next launch.
enum OnboardingRegistry {
    static let steps: [OnboardingStep] = [
        OnboardingStep(id: .migration, weight: 5, version: 1, tracksSeen: false) {
            $0.hasDataToMigrate && $0.shouldPerformMigration
        },
        OnboardingStep(id: .welcome, weight: 10, version: 1) { _ in true },
        OnboardingStep(id: .location, weight: 20, version: 1) {
            !$0.locationAuthorizationDetermined
        },
        OnboardingStep(id: .region, weight: 30, version: 1) { _ in true },
        OnboardingStep(id: .notifications, weight: 40, version: 1) {
            $0.isPushServiceConfigured && !$0.notificationAuthorizationDetermined
        },
        // Tells people who used the tab bar where Settings and More went when the
        // map panel became the default. Nobody on the tab bar sees it, and neither
        // does a new install: see `existingUserOnlyStepIDs`.
        OnboardingStep(id: .mapPanelIntro, weight: 50, version: 1) {
            $0.hasCurrentRegion && $0.usesMapPanelExperience
        },
        OnboardingStep(id: .done, weight: 99, version: 1) { _ in true }
    ]

    /// Steps that introduce a change to people who used the app before it. A new
    /// install has nothing to compare against, so `evaluate` marks these seen when
    /// it finds no region; otherwise they would greet a new user on their second
    /// launch, once onboarding had given them one.
    static let existingUserOnlyStepIDs: Set<OnboardingStepID> = [.mapPanelIntro]

    /// Marks `existingUserOnlyStepIDs` seen at their registry versions. Call for a
    /// new install (no region), before computing its flow.
    @MainActor
    static func skipExistingUserOnlySteps(steps: [OnboardingStep] = Self.steps, store: OnboardingStepStore) {
        for step in steps where existingUserOnlyStepIDs.contains(step.id) {
            store.markSeen(step.id, version: step.version)
        }
    }

    @MainActor
    static func flow(
        steps: [OnboardingStep] = Self.steps,
        environment: OnboardingEnvironment,
        store: OnboardingStepStore
    ) -> [OnboardingStep] {
        steps
            .filter { step in
                guard step.isEligible(environment) else { return false }
                guard step.tracksSeen else { return true }
                return store.seenVersion(of: step.id) < step.version
            }
            .sorted { $0.weight < $1.weight }
    }
}
