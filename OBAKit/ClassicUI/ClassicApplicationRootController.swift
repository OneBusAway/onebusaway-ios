//
//  ClassicApplicationRootController.swift
//  OBANext
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
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
    private let useMapPanel: Bool

    @objc public init(application: Application) {
        self.application = application

        let useMapPanel = application.userDefaults.bool(forKey: FeatureFlags.useMapPanelExperienceKey)
        self.useMapPanel = useMapPanel

        if useMapPanel {
            // Map panel experience — the tab bar is discarded and the SwiftUI
            // map (with the floating sheet) occupies the whole screen.
            self.mapController = nil
            self.recentStopsController = nil
            self.bookmarksController = nil
            self.moreController = nil

            super.init(nibName: nil, bundle: nil)

            self.tabBar.isHidden = true

            self.application.viewRouter.rootController = self

            let host = UIHostingController(rootView: MapPanelRootView(application: application))
            viewControllers = [host]
        } else {
            let mapController = MapViewController(application: application)
            let recentStopsController = RecentStopsViewController(application: application)
            let bookmarksController = BookmarksViewController(application: application)
            let moreController = MoreViewController(application: application)

            self.mapController = mapController
            self.recentStopsController = recentStopsController
            self.bookmarksController = bookmarksController
            self.moreController = moreController

            super.init(nibName: nil, bundle: nil)

            if #available(iOS 26.0, *) {
                self.tabBar.isTranslucent = true
            } else {
                self.tabBar.isTranslucent = false
            }

            self.application.viewRouter.rootController = self

            let mapNav = application.viewRouter.buildNavigation(controller: mapController, prefersLargeTitles: false)
            let recentStopsNav = application.viewRouter.buildNavigation(controller: recentStopsController)
            let bookmarksNav = application.viewRouter.buildNavigation(controller: bookmarksController)
            let moreNav = application.viewRouter.buildNavigation(controller: moreController)

            viewControllers = [mapNav, recentStopsNav, bookmarksNav, moreNav]

            selectedIndex = application.userDataStore.lastSelectedView.rawValue
        }
    }

    /// Non-nil only when the classic UIKit experience is active.
    /// In map panel mode, the tab bar and these tab VCs are not constructed.
    let mapController: MapViewController?
    let recentStopsController: RecentStopsViewController?
    let bookmarksController: BookmarksViewController?
    let moreController: MoreViewController?

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
        // Only available with the classic UIKit map.
        if let mapController, let root = (selectedViewController as? UINavigationController)?.viewControllers.first,
            root === mapController,
            selectedTab == .map {
            mapController.centerMapOnUserLocation()
        }

        application.userDataStore.lastSelectedView = selectedTab
    }

    func navigate(to destination: Page) {
        // In map panel mode there are no per-page tabs to switch to.
        guard !useMapPanel else { return }
        navigationController?.popToViewController(self, animated: true)
        selectedIndex = destination.rawValue
    }
}
