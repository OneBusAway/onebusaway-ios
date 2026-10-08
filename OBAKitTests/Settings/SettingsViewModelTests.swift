//
//  SettingsViewModelTests.swift
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

/// The rules that tie Settings rows to each other, and the write-through that
/// replaced saving on dismissal. HealthKit and the Experimental flags have
/// their own suites.
@MainActor
@Suite(.serialized)
final class SettingsViewModelTests: OBATestCase {

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
        SettingsViewModel(application: application, isHealthKitAvailable: false)
    }

    private var defaults: UserDefaults { application.userDefaults }

    // MARK: - Debug Mode

    @Test func `Turning debug mode off turns off what it exposed`() {
        let vm = makeViewModel()
        vm.debugMode = true
        vm.alwaysRefreshesRegionsOnLaunch = true
        vm.testDeviceName = "QA iPhone"
        vm.displaysTestAlerts = true
        vm.alwaysShowsFeedbackPrompt = true

        vm.debugMode = false

        #expect(!self.application.userDataStore.debugMode)
        #expect(!self.defaults.bool(forKey: RegionsService.alwaysRefreshRegionsOnLaunchUserDefaultsKey))
        #expect(!self.defaults.bool(forKey: AgencyAlertsStore.UserDefaultKeys.displayRegionalTestAlerts))
        #expect(!self.application.reviewPromptPolicy.alwaysShowPrompt)
        #expect(!vm.displaysTestAlerts)
    }

    @Test func `Turning debug mode on leaves the debug settings alone`() {
        let vm = makeViewModel()
        vm.alwaysRefreshesRegionsOnLaunch = true

        vm.debugMode = true

        #expect(vm.alwaysRefreshesRegionsOnLaunch)
        #expect(self.defaults.bool(forKey: RegionsService.alwaysRefreshRegionsOnLaunchUserDefaultsKey))
    }

    // MARK: - Test device

    @Test func `Clearing the test device name turns test alerts off`() {
        let vm = makeViewModel()
        vm.testDeviceName = "QA iPhone"
        vm.displaysTestAlerts = true
        #expect(vm.hasTestDeviceName)

        vm.testDeviceName = "  "

        #expect(!vm.hasTestDeviceName)
        #expect(!vm.displaysTestAlerts)
        #expect(!self.defaults.bool(forKey: AgencyAlertsStore.UserDefaultKeys.displayRegionalTestAlerts))
        #expect(self.defaults.string(forKey: PushRegistrationManager.testDeviceDescriptionDefaultsKey) == "  ")
    }

    // MARK: - Write-through

    @Test func `Opening settings writes nothing`() {
        application.userDataStore.walkingSpeedMetersPerSecond = 1.55
        application.userDataStore.walkingSpeedSource = .manual

        _ = makeViewModel()

        // Seeding snaps the picker to a preset, but must not persist the snap.
        expectClose(self.application.userDataStore.walkingSpeedMetersPerSecond, 1.55)
    }

    @Test func `Picking a walking speed saves it`() {
        application.userDataStore.walkingSpeedSource = .manual
        let vm = makeViewModel()

        vm.walkingSpeed = .fast

        expectClose(self.application.userDataStore.walkingSpeedMetersPerSecond, WalkingSpeedPreset.fast.rawValue)
        #expect(self.application.userDataStore.walkingSpeedSource == .manual)
    }

    @Test func `Settings seed from and save to the store`() {
        application.userDataStore.showTransferArrivalBanner = true
        let vm = makeViewModel()
        #expect(vm.showsTransferArrivalBanner)

        vm.showsTransferArrivalBanner = false
        vm.reducesStopColors = true
        vm.mapShowsScale = true

        #expect(!self.application.userDataStore.showTransferArrivalBanner)
        #expect(self.application.userDataStore.stopUIReducedColors)
        #expect(self.application.mapRegionManager.mapViewShowsScale)
    }
}
