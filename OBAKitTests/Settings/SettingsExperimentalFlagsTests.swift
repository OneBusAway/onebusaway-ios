//
//  SettingsExperimentalFlagsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

@testable import OBAKit
@testable import OBAKitCore
import Foundation
import Testing

/// The Experimental toggles are the only writers of their feature-flag defaults, and the section's
/// footer invites you to relaunch the app the moment you flip one. So the flag has to be on disk
/// *before* the screen goes away: these tests flip the switch and read UserDefaults back without
/// dismissing anything.
@MainActor
@Suite(.serialized)
final class SettingsExperimentalFlagsTests: OBATestCase {

    private var queue: OperationQueue!
    private var application: Application!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    private func makeViewModel() -> SettingsViewModel {
        SettingsViewModel(application: application)
    }

    // MARK: - Map panel

    @Test func `Map panel seeds on by default`() throws {
        application.userDefaults.removeObject(forKey: FeatureFlags.useMapPanelExperienceKey)
        let vm = makeViewModel()
        #expect(vm.usesMapPanelExperience)
        #expect(FeatureFlags.isMapPanelExperienceEnabled(userDefaults: self.application.userDefaults))
    }

    @Test func `Map panel toggling off opts out and persists immediately`() throws {
        application.userDefaults.removeObject(forKey: FeatureFlags.useMapPanelExperienceKey)
        let vm = makeViewModel()
        vm.usesMapPanelExperience = false

        #expect(self.application.userDefaults.object(forKey: FeatureFlags.useMapPanelExperienceKey) as? Bool == false)
        #expect(!FeatureFlags.isMapPanelExperienceEnabled(userDefaults: self.application.userDefaults))
    }

    /// UI tests opt out with `-OBAUseMapPanelExperience NO`, which the
    /// argument domain hands over as a string.
    @Test func `Map panel honours a string NO from a launch argument`() throws {
        application.userDefaults.set("NO", forKey: FeatureFlags.useMapPanelExperienceKey)
        #expect(!FeatureFlags.isMapPanelExperienceEnabled(userDefaults: self.application.userDefaults))
    }

    @Test func `Map panel toggling back on persists immediately`() throws {
        application.userDefaults.set(false, forKey: FeatureFlags.useMapPanelExperienceKey)
        let vm = makeViewModel()
        vm.usesMapPanelExperience = true

        #expect(FeatureFlags.isMapPanelExperienceEnabled(userDefaults: self.application.userDefaults))
    }

    // MARK: - Stop clustering

    @Test func `Stop clustering seeds off by default`() throws {
        let vm = makeViewModel()
        #expect(!vm.clustersStops)
    }

    @Test func `Stop clustering toggling on persists immediately`() throws {
        let vm = makeViewModel()
        vm.clustersStops = true

        #expect(self.application.userDefaults.bool(forKey: FeatureFlags.clustersStopsKey))
    }

    // MARK: - Accessibility

    /// This switch was once wired to neither seeding nor saving, so it always drew "off" and
    /// never wrote anything.
    @Test func `Voiceover full sheet round trips through the form`() throws {
        application.userDefaults.set(true, forKey: OBAFloatingPanelController.AlwaysShowFullSheetOnVoiceoverUserDefaultsKey)
        let vm = makeViewModel()
        #expect(vm.alwaysShowsFullSheetOnVoiceOver == true)

        vm.alwaysShowsFullSheetOnVoiceOver = false

        #expect(!self.application.userDefaults.bool(forKey: OBAFloatingPanelController.AlwaysShowFullSheetOnVoiceoverUserDefaultsKey))
    }
}
