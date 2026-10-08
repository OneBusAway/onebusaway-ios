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

    // MARK: - New stop page

    @Test func `New stop page seeds on by default`() throws {
        let vm = makeViewModel()
        #expect(vm.usesNewStopPage)
    }

    /// The failing case before this was fixed: toggle off, then kill the app to "restart to apply"
    /// without ever dismissing Settings. `viewWillDisappear` never runs, so nothing was written.
    @Test func `New stop page toggling off persists immediately`() throws {
        let vm = makeViewModel()
        vm.usesNewStopPage = false

        #expect(!FeatureFlags.isNewStopPageEnabled(userDefaults: self.application.userDefaults))
    }

    @Test func `New stop page toggling back on persists immediately`() throws {
        application.userDefaults.set(false, forKey: FeatureFlags.useNewStopPageKey)
        let vm = makeViewModel()
        vm.usesNewStopPage = true

        #expect(FeatureFlags.isNewStopPageEnabled(userDefaults: self.application.userDefaults))
    }

    // MARK: - Map panel

    @Test func `Map panel toggling on persists immediately`() throws {
        let vm = makeViewModel()
        vm.usesMapPanelExperience = true

        #expect(self.application.userDefaults.bool(forKey: FeatureFlags.useMapPanelExperienceKey))
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
