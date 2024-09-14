//
//  ClassicApplicationRootController.swift
//  OBANext
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore

@objc(OBAClassicApplicationRootController)
public class ClassicApplicationRootController: UITabBarController {
    public enum Page: Int {
        case map = 0
        case recentStops
        case bookmarks
        case tripPlanner
        case more
    }

    private let application: Application

    @objc public init(application: Application) {
        self.application = application
        super.init(nibName: nil, bundle: nil)
        self.application.viewRouter.rootController = self
        setupControllers()
        observeTripPlannerServiceChanges()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private lazy var mapController: MapViewController = {
        MapViewController(application: application)
    }()

    private lazy var recentStopsController: RecentStopsViewController = {
        RecentStopsViewController(application: application)
    }()

    private lazy var bookmarksController: BookmarksViewController = {
        BookmarksViewController(application: application)
    }()

    private lazy var moreController: MoreViewController = {
        MoreViewController(application: application)
    }()

    private var currentViewControllers: [UIViewController] {
        let mapNav = application.viewRouter.buildNavigation(controller: mapController, prefersLargeTitles: false)
        let recentStopsNav = application.viewRouter.buildNavigation(controller: recentStopsController)
        let bookmarksNav = application.viewRouter.buildNavigation(controller: bookmarksController)
        let moreNav = application.viewRouter.buildNavigation(controller: moreController)

        var controllers = [mapNav, recentStopsNav, bookmarksNav, moreNav]

        if let tripPlannerService = application.tripPlannerService {
            let tripPlannerController = TripPlannerHostingController(tripPlannerService: tripPlannerService)
            let tripPlannerNav = application.viewRouter.buildNavigation(controller: tripPlannerController)
            controllers.insert(tripPlannerNav, at: 3) // Insert before 'more'
        }

        return controllers
    }

    private func setupControllers() {
        updateViewControllers()
    }

    private func observeTripPlannerServiceChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateViewControllers),
            name: .tripPlannerServiceDidChange,
            object: application
        )
    }

    @objc private func updateViewControllers() {
        let newViewControllers = currentViewControllers

        if newViewControllers != viewControllers {
            viewControllers = newViewControllers

            // Ensure the selected index is still valid
            if selectedIndex >= newViewControllers.count {
                selectedIndex = 0
            }

            application.userDataStore.lastSelectedView = SelectedTab(rawValue: selectedIndex) ?? .map
        }
    }

    public override func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        guard
            let itemIndex = tabBar.items?.firstIndex(of: item),
            let selectedTab = SelectedTab(rawValue: itemIndex)
        else {
            return
        }

        // If the user is already on the map tab and they tap on the map tab item again, then zoom to their location.
        if let root = (selectedViewController as? UINavigationController)?.viewControllers.first, root == mapController, selectedTab == .map {
            mapController.centerMapOnUserLocation()
        }

        application.userDataStore.lastSelectedView = selectedTab
    }

    func navigate(to destination: Page) {
        navigationController?.popToViewController(self, animated: true)
        selectedIndex = destination.rawValue
    }
}
