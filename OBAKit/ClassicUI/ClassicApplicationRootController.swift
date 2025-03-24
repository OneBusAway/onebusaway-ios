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
        case more
    }

    private let application: Application

    @objc public init(application: Application) {
        self.application = application

        self.mapController = MapViewController(application: application)
        self.recentStopsController = RecentStopsViewController(application: application)
        self.bookmarksController = BookmarksViewController(application: application)
        self.moreController = MoreViewController(application: application)

        super.init(nibName: nil, bundle: nil)

        self.application.viewRouter.rootController = self

        let mapNav = application.viewRouter.buildNavigation(controller: self.mapController, prefersLargeTitles: false)
        let recentStopsNav = application.viewRouter.buildNavigation(controller: self.recentStopsController)
        let bookmarksNav = application.viewRouter.buildNavigation(controller: self.bookmarksController)
        let moreNav = application.viewRouter.buildNavigation(controller: self.moreController)

        viewControllers = [mapNav, recentStopsNav, bookmarksNav, moreNav]

        selectedIndex = application.userDataStore.lastSelectedView.rawValue
    }

    let mapController: MapViewController
    let recentStopsController: RecentStopsViewController
    let bookmarksController: BookmarksViewController
    let moreController: MoreViewController

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
