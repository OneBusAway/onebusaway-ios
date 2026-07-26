//
//  SettingsExperimentalFlagsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Eureka
import XCTest
@testable import OBAKit
@testable import OBAKitCore
import Nimble

/// The Experimental toggles are the only writers of their feature-flag defaults, and the section's
/// footer invites you to relaunch the app the moment you flip one. So the flag has to be on disk
/// *before* the screen goes away: these tests flip the switch and read UserDefaults back without
/// dismissing anything.
@MainActor
final class SettingsExperimentalFlagsTests: OBATestCase {

    private var queue: OperationQueue!
    private var application: Application!

    override func setUp() async throws {
        try await super.setUp()
        queue = OperationQueue()
        application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
    }

    override func tearDown() async throws {
        queue.cancelAllOperations()
        queue = nil
        application = nil
        try await super.tearDown()
    }

    private func makeLoadedController() -> SettingsViewController {
        let controller = SettingsViewController(application: application)
        controller.loadViewIfNeeded()
        return controller
    }

    private func row(_ controller: SettingsViewController, _ tag: String) throws -> SwitchRow {
        try XCTUnwrap(controller.form.rowBy(tag: tag) as? SwitchRow)
    }

    // MARK: - New stop page

    func test_newStopPage_seedsOnByDefault() throws {
        let controller = makeLoadedController()
        expect(try self.row(controller, FeatureFlags.useNewStopPageKey).value).to(beTrue())
    }

    /// The failing case before this was fixed: toggle off, then kill the app to "restart to apply"
    /// without ever dismissing Settings. `viewWillDisappear` never runs, so nothing was written.
    func test_newStopPage_togglingOffPersistsImmediately() throws {
        let controller = makeLoadedController()
        try row(controller, FeatureFlags.useNewStopPageKey).value = false

        expect(FeatureFlags.isNewStopPageEnabled(userDefaults: self.application.userDefaults)).to(beFalse())
    }

    func test_newStopPage_togglingBackOnPersistsImmediately() throws {
        application.userDefaults.set(false, forKey: FeatureFlags.useNewStopPageKey)
        let controller = makeLoadedController()
        try row(controller, FeatureFlags.useNewStopPageKey).value = true

        expect(FeatureFlags.isNewStopPageEnabled(userDefaults: self.application.userDefaults)).to(beTrue())
    }

    func test_newStopPage_stillPersistsOnDismissal() throws {
        let controller = makeLoadedController()
        try row(controller, FeatureFlags.useNewStopPageKey).value = false
        controller.viewWillDisappear(false)

        expect(FeatureFlags.isNewStopPageEnabled(userDefaults: self.application.userDefaults)).to(beFalse())
    }

    // MARK: - Map panel

    func test_mapPanel_togglingOnPersistsImmediately() throws {
        let controller = makeLoadedController()
        try row(controller, FeatureFlags.useMapPanelExperienceKey).value = true

        expect(self.application.userDefaults.bool(forKey: FeatureFlags.useMapPanelExperienceKey)).to(beTrue())
    }

    // MARK: - Accessibility

    /// This row was wired to neither `setValues` nor `saveFormValues`, so it always drew "off" and
    /// never wrote anything.
    func test_voiceoverFullSheet_roundTripsThroughTheForm() throws {
        application.userDefaults.set(true, forKey: OBAFloatingPanelController.AlwaysShowFullSheetOnVoiceoverUserDefaultsKey)
        let controller = makeLoadedController()
        let switchRow = try row(controller, OBAFloatingPanelController.AlwaysShowFullSheetOnVoiceoverUserDefaultsKey)
        expect(switchRow.value).to(beTrue())

        switchRow.value = false
        controller.viewWillDisappear(false)

        expect(self.application.userDefaults.bool(forKey: OBAFloatingPanelController.AlwaysShowFullSheetOnVoiceoverUserDefaultsKey)).to(beFalse())
    }
}
