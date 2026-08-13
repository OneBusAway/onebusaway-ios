//
//  SettingsExperimentalFlagsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Eureka
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

    private func makeLoadedController() -> SettingsViewController {
        let controller = SettingsViewController(application: application)
        controller.loadViewIfNeeded()
        return controller
    }

    private func row(_ controller: SettingsViewController, _ tag: String) throws -> SwitchRow {
        try #require(controller.form.rowBy(tag: tag) as? SwitchRow)
    }

    // MARK: - New stop page

    @Test func `New stop page seeds on by default`() throws {
        let controller = makeLoadedController()
        // `value` is Eureka's `Bool?`; `== true` keeps Nimble's beTrue semantics,
        // where a nil value is a failure rather than a pass.
        #expect(try self.row(controller, FeatureFlags.useNewStopPageKey).value == true)
    }

    /// The failing case before this was fixed: toggle off, then kill the app to "restart to apply"
    /// without ever dismissing Settings. `viewWillDisappear` never runs, so nothing was written.
    @Test func `New stop page toggling off persists immediately`() throws {
        let controller = makeLoadedController()
        try row(controller, FeatureFlags.useNewStopPageKey).value = false

        #expect(!FeatureFlags.isNewStopPageEnabled(userDefaults: self.application.userDefaults))
    }

    @Test func `New stop page toggling back on persists immediately`() throws {
        application.userDefaults.set(false, forKey: FeatureFlags.useNewStopPageKey)
        let controller = makeLoadedController()
        try row(controller, FeatureFlags.useNewStopPageKey).value = true

        #expect(FeatureFlags.isNewStopPageEnabled(userDefaults: self.application.userDefaults))
    }

    @Test func `New stop page still persists on dismissal`() throws {
        let controller = makeLoadedController()
        try row(controller, FeatureFlags.useNewStopPageKey).value = false
        controller.viewWillDisappear(false)

        #expect(!FeatureFlags.isNewStopPageEnabled(userDefaults: self.application.userDefaults))
    }

    // MARK: - Map panel

    @Test func `Map panel toggling on persists immediately`() throws {
        let controller = makeLoadedController()
        try row(controller, FeatureFlags.useMapPanelExperienceKey).value = true

        #expect(self.application.userDefaults.bool(forKey: FeatureFlags.useMapPanelExperienceKey))
    }

    // MARK: - Accessibility

    /// This row was wired to neither `setValues` nor `saveFormValues`, so it always drew "off" and
    /// never wrote anything.
    @Test func `Voiceover full sheet round trips through the form`() throws {
        application.userDefaults.set(true, forKey: OBAFloatingPanelController.AlwaysShowFullSheetOnVoiceoverUserDefaultsKey)
        let controller = makeLoadedController()
        let switchRow = try row(controller, OBAFloatingPanelController.AlwaysShowFullSheetOnVoiceoverUserDefaultsKey)
        #expect(switchRow.value == true)

        switchRow.value = false
        controller.viewWillDisappear(false)

        #expect(!self.application.userDefaults.bool(forKey: OBAFloatingPanelController.AlwaysShowFullSheetOnVoiceoverUserDefaultsKey))
    }
}
