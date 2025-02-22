//
//  OnboardingNavigationController.swift
//  OneBusAway
//
//  Created by Alan Chu on 1/28/23.
//

import OBAKit
import OBAKitCore
import SwiftUI

/// Displays Onboarding steps. For performance, consider checking ``needsToOnboard(application:)`` before initializing and presenting this controller.
/// This is the default Onboarder, created for migrating data from the classic-codebase and for selecting a region from a list.
@objc(OBAOnboardingNavigationController)
public class OnboardingNavigationController: UINavigationController {
    enum Page: UInt, CaseIterable {
        case migration
        case location
        case regionPicker

        case debugPageA
        case debugPageB
    }

    private let application: Application
    private let regionsService: RegionsService
    private let regionPickerCoordinator: RegionPickerCoordinator
    private let dataMigrator: DataMigrator

    private var page: Page?

    var completion: VoidBlock

    private static var testOnboarding: Bool = {
        #if DEBUG
        let envVar = ProcessInfo.processInfo.environment["TEST_ONBOARDING"] ?? "0"
        return (envVar as NSString).boolValue
        #else
        return false
        #endif
    }()

    @objc static public func needsToOnboard(application: Application) -> Bool {
        if testOnboarding {
            return true
        }

        return application.regionsService.currentRegion == nil || application.shouldPerformMigration
    }

    public init(application: Application, dataMigrator: DataMigrator = .standard, completion: @escaping VoidBlock) {
        self.application = application
        self.regionsService = application.regionsService
        self.regionPickerCoordinator = RegionPickerCoordinator(regionsService: regionsService)
        self.dataMigrator = dataMigrator

        self.completion = completion

        super.init(nibName: nil, bundle: nil)
    }

    @objc public convenience init(application: Application, completion: @escaping VoidBlock) {
        self.init(application: application, dataMigrator: .standard, completion: completion)
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        if application.hasDataToMigrate {
            self.page = .migration
        } else if application.regionsService.currentRegion == nil || Self.testOnboarding {
            self.page = .location
        } else {
            self.page =  nil
        }

        self.showPage()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @ViewBuilder private func view(for page: Page) -> some View {
        let dismissBlock: VoidBlock = { [weak self] in
            self?.nextPage()
        }

        switch page {
        case .location:
            RegionPickerLocationAuthorizationView(regionProvider: regionPickerCoordinator, dismissBlock: dismissBlock)
        case .regionPicker:
            RegionPickerView(regionProvider: regionPickerCoordinator, dismissBlock: dismissBlock)
        case .migration:
            DataMigrationView(dismissBlock: dismissBlock)
        case .debugPageA:
            Button("Debug A", action: dismissBlock)
        case .debugPageB:
            Button("Debug B", action: dismissBlock)
        }
    }

    private func showPage() {
        guard let page else {
            return self.dismiss(animated: true, completion: self.completion)
        }

        let view = view(for: page)
            .environment(\.coreApplication, application)

        self.setViewControllers([UIHostingController(rootView: view)], animated: true)
    }

    private func nextPage() {
        guard let page else {
            return
        }

        switch page {
        case .migration:
            self.page = .location
        case .location:
            self.page = .regionPicker
        case .regionPicker:
            if Self.testOnboarding {
                self.page = .debugPageA
            } else {
                self.page = nil
            }
        case .debugPageA:
            self.page = .debugPageB
        case .debugPageB:
            self.page = nil
        }

        self.showPage()
    }
}
