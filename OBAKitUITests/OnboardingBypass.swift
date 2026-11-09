//
//  OnboardingBypass.swift
//  OBAKitUITests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Launch arguments that put the app past onboarding on a clean simulator.
///
/// Injecting the current region is not enough. `OnboardingStepStore.backfillIfNeeded`
/// only marks `.welcome`, `.location`, `.region` and `.done` as seen, deliberately
/// leaving `.notifications` out, and that step is eligible whenever a push service is
/// configured and notification authorization is still undetermined. Both hold on a
/// fresh simulator, so the app launches into "Stay ahead of disruptions" and no test
/// that waits on the main UI can ever pass.
///
/// Writing the seen-version store directly through the UserDefaults argument domain
/// makes every registry step seen, so the computed flow is empty. The keys mirror
/// `OnboardingStepID`'s raw values; a UI test bundle cannot import OBAKit's internals,
/// so adding a step to the registry means adding it here too.
/// `nonisolated` so the `nonisolated` XCTestCase subclasses can read it: the target
/// defaults to main-actor isolation, which would otherwise make these properties
/// unreachable from `setUpWithError()`.
nonisolated enum OnboardingBypass {

    /// Keep in sync with `OnboardingStepID`. `.migration` is omitted on purpose: it
    /// does not track seen state and is only eligible when there is data to migrate.
    private static let seenStepVersions = """
        <dict>\
        <key>welcome</key><integer>1</integer>\
        <key>location</key><integer>1</integer>\
        <key>region</key><integer>1</integer>\
        <key>notifications</key><integer>1</integer>\
        <key>done</key><integer>1</integer>\
        </dict>
        """

    /// Puget Sound, which is bundled in regions.json.
    static let launchArguments: [String] = [
        "-AppleLanguages", "(en)",
        "-OBACurrentRegionIdentifierUserDefaultsKey", "<integer>1</integer>",
        "-OBAOnboardingSeenStepVersions", seenStepVersions
    ]
}
