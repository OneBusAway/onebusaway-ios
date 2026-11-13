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
/// replaced saving on dismissal. Speed sync and the Experimental flags have
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
        SettingsViewModel(application: application)
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

    @Test func `Walking directions asks by default and ignores an unknown saved provider`() {
        #expect(makeViewModel().walkingDirectionsProvider == .askEveryTime)
        #expect(self.defaults.object(forKey: WalkingDirectionsProvider.defaultsKey) == nil)

        defaults.set("unknown-provider", forKey: WalkingDirectionsProvider.defaultsKey)
        #expect(makeViewModel().walkingDirectionsProvider == .askEveryTime)
    }

    @Test(arguments: WalkingDirectionsProvider.allCases)
    func `Walking directions provider is saved and restored when settings reopens`(provider: WalkingDirectionsProvider) {
        let vm = makeViewModel()
        vm.walkingDirectionsProvider = provider

        #expect(self.defaults.string(forKey: WalkingDirectionsProvider.defaultsKey) == provider.rawValue)
        #expect(makeViewModel().walkingDirectionsProvider == provider)
    }

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
        application.userDataStore.highlightTransferTrip = true
        let vm = makeViewModel()
        #expect(vm.highlightsTransferTrip)

        vm.highlightsTransferTrip = false
        vm.reducesStopColors = true
        vm.mapShowsScale = true

        #expect(!self.application.userDataStore.highlightTransferTrip)
        #expect(self.application.userDataStore.stopUIReducedColors)
        #expect(self.application.mapRegionManager.mapViewShowsScale)
    }

    @Test func `Turning walking sync off saves manual at the preset on screen`() {
        application.userDataStore.walkingSpeedSource = .synced
        application.userDataStore.walkingSpeedMetersPerSecond = 1.65
        let vm = SettingsViewModel(application: application)
        #expect(vm.walkingSpeed == .fast)

        vm.walkingSpeedIsSynced = false

        #expect(self.application.userDataStore.walkingSpeedSource == .manual)
        expectClose(self.application.userDataStore.walkingSpeedMetersPerSecond, WalkingSpeedPreset.fast.rawValue)
    }

    /// A sync that lands while Settings is open changes the stored speed after `init`
    /// seeded the picker; turning sync off must snap the synced speed, not the seed.
    @Test func `Turning walking sync off snaps the speed synced during this visit`() {
        application.userDataStore.walkingSpeedSource = .synced
        application.userDataStore.walkingSpeedMetersPerSecond = 0.9
        let vm = SettingsViewModel(application: application)
        #expect(vm.walkingSpeed == .slow)

        // What WalkingSpeedManager writes when a sample lands.
        application.userDataStore.walkingSpeedMetersPerSecond = 1.75

        vm.walkingSpeedIsSynced = false

        #expect(vm.walkingSpeed == .fast)
        expectClose(self.application.userDataStore.walkingSpeedMetersPerSecond, WalkingSpeedPreset.fast.rawValue)
    }
}
