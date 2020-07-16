//
//  Onboarder.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 5/9/20.
//

import Foundation
import OBAKitCore
import BLTNBoard

enum OnboardingState {
    case unknown, locationPermissionPrompt, manualRegionSelection, dataMigration, complete
}

class Onboarder: NSObject {
    private let locationService: LocationService
    private let regionsService: RegionsService
    private let dataMigrator: DataMigrator

    init(locationService: LocationService, regionsService: RegionsService, dataMigrator: DataMigrator) {
        self.locationService = locationService
        self.regionsService = regionsService
        self.dataMigrator = dataMigrator
    }

    func show(in application: UIApplication) {
        // Don’t show another RegionPickerBulletin if one already exists and is being presented.
        guard !bulletinManager.isShowingBulletin else { return }

        bulletinManager.showBulletin(in: application)
    }

    // MARK: - Onboarding UI

    private lazy var bulletinManager = BLTNItemManager(rootItem: currentBulletinPage)

    private var currentBulletinPage: BLTNPageItem {
        switch state {
        case .locationPermissionPrompt: return locationPermissionItem
        case .manualRegionSelection: return regionPickerItem
        case .dataMigration: return dataMigrationItem
        default:
            fatalError()
        }
    }

    private func refreshUI() {
        guard state != .complete else {
            bulletinManager.dismissBulletin()
            return
        }

        bulletinManager.push(item: currentBulletinPage)
    }

    // MARK: - Location Permission Item

    private lazy var locationPermissionItem = LocationPermissionItem(locationService: locationService) { [weak self] in
        guard let self = self else { return }
        self.refreshUI()
    }

    // MARK: - RegionPickerItem

    private lazy var regionPickerItem = RegionPickerItem(regionsService: regionsService)

    // MARK: - DataMigrationItem

    private lazy var dataMigrationItem = DataMigrationBulletinPage(dataMigrator: dataMigrator) { [weak self] in
        guard let self = self else { return }
        self.refreshUI()
    }

    // MARK: - State Logic

    public var onboardingRequired: Bool {
        state != .complete
    }

    var state: OnboardingState {
        if showPermissionPromptUI {
            return .locationPermissionPrompt
        }
        else if showRegionPicker {
            return .manualRegionSelection
        }
        else if showMigrator {
            return .dataMigration
        }
        else {
            return .complete
        }
    }

    /// True when the app should show an interstitial location service permission
    /// request user interface. Meant to be called on app launch to determine
    /// which piece of UI should be shown initially.
    private var showPermissionPromptUI: Bool {
        return locationService.canRequestAuthorization && locationService.canPromptUserForPermission
    }

    private var showRegionPicker: Bool {
        regionsService.currentRegion == nil
    }

    private var showMigrator: Bool {
        dataMigrator.shouldPerformMigration
    }
}
