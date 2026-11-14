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
import UIKit
import Testing

/// The Experimental toggles are the only writers of their feature-flag defaults, and the map panel
/// toggle rebuilds the window's root from its flag the moment you flip it. So the flag has to be on
/// disk *before* the screen goes away: these tests flip the switch and read UserDefaults back without
/// dismissing anything.
@MainActor
@Suite(.serialized)
final class SettingsExperimentalFlagsTests: OBATestCase {

    private var queue: OperationQueue!
    private var application: Application!
    private var appDelegate: RootReloadRecorder!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        appDelegate = RootReloadRecorder()
        application.delegate = appDelegate
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

    // MARK: - Map panel root swap

    @Test func `Turning the map panel off swaps in the classic root at once`() throws {
        application.userDefaults.removeObject(forKey: FeatureFlags.useMapPanelExperienceKey)
        let vm = makeViewModel()
        var dismissals = 0
        vm.dismissSettings = { completion in
            dismissals += 1
            completion()
        }

        vm.usesMapPanelExperience = false

        #expect(dismissals == 1)
        #expect(appDelegate.reloads == 1)
        #expect(appDelegate.root is ClassicApplicationRootController)
    }

    @Test func `Turning the map panel back on swaps in the panel root at once`() throws {
        application.userDefaults.set(false, forKey: FeatureFlags.useMapPanelExperienceKey)
        let vm = makeViewModel()

        vm.usesMapPanelExperience = true

        #expect(appDelegate.reloads == 1)
        #expect(appDelegate.root is MapPanelRootController)
    }

    /// Settings is presented inside the root being replaced.
    @Test func `The root is swapped only after Settings is dismissed`() throws {
        application.userDefaults.removeObject(forKey: FeatureFlags.useMapPanelExperienceKey)
        let vm = makeViewModel()
        var finishDismissal: (() -> Void)?
        vm.dismissSettings = { finishDismissal = $0 }

        vm.usesMapPanelExperience = false
        #expect(appDelegate.reloads == 0)

        let finish = try #require(finishDismissal)
        finish()
        #expect(appDelegate.reloads == 1)
    }

    @Test func `Setting the map panel to its current value leaves the root alone`() throws {
        application.userDefaults.removeObject(forKey: FeatureFlags.useMapPanelExperienceKey)
        let vm = makeViewModel()

        vm.usesMapPanelExperience = true

        #expect(appDelegate.reloads == 0)
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

    // MARK: - Estimated vehicle positions

    @Test func `Vehicle position estimation seeds off by default`() throws {
        let vm = makeViewModel()
        #expect(!vm.estimatesVehiclePositions)
        #expect(!FeatureFlags.isVehicleEstimationEnabled(userDefaults: application.userDefaults))
    }

    @Test func `Vehicle position estimation toggling on persists immediately`() throws {
        let vm = makeViewModel()
        vm.estimatesVehiclePositions = true
        #expect(FeatureFlags.isVehicleEstimationEnabled(userDefaults: application.userDefaults))
    }

    @Test func `The raw vehicle fix overlay seeds off and persists`() throws {
        let vm = makeViewModel()
        #expect(!vm.showsRawVehicleFix)
        vm.showsRawVehicleFix = true
        #expect(FeatureFlags.showsRawVehicleFix(userDefaults: application.userDefaults))
    }
}

/// Stands in for the app delegate: counts root reloads, and builds the root
/// from the flag the way the apps' `RootInterfaceLauncher` does.
@MainActor
private final class RootReloadRecorder: NSObject, ApplicationDelegate {
    var uiApplication: UIApplication?
    var isIdleTimerDisabled = false
    var isRegisteredForRemoteNotifications = false

    private(set) var reloads = 0
    private(set) var root: UIViewController?

    func applicationReloadRootInterface(_ app: Application) {
        reloads += 1
        root = ApplicationRootControllerFactory.make(application: app)
    }

    func canOpenURL(_ url: URL) -> Bool { false }

    func open(_ url: URL, options: [UIApplication.OpenExternalURLOptionsKey: Any], completionHandler completion: ((Bool) -> Void)?) {}
}
