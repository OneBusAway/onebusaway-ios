//
//  ClassicApplicationRootController.swift
//  OBANext
//
//  Created by Aaron Brethorst on 4/22/19.
//

import UIKit

@objc(OBAClassicApplicationRootController)
public class ClassicApplicationRootController: UITabBarController {
    private let application: Application

    @objc public init(application: Application) {
        self.application = application

        self.mapController = MapViewController(application: application)
        self.recentStopsController = RecentStopsViewController(application: application)
        self.bookmarksController = BookmarksViewController(application: application)
        self.moreController = MoreViewController(application: application)

        super.init(nibName: nil, bundle: nil)

        let mapNav = application.viewRouter.buildNavigation(controller: self.mapController, prefersLargeTitles: false)
        let recentStopsNav = application.viewRouter.buildNavigation(controller: self.recentStopsController)
        let bookmarksNav = application.viewRouter.buildNavigation(controller: self.bookmarksController)
        let moreNav = application.viewRouter.buildNavigation(controller: self.moreController)

        self.viewControllers = [mapNav, recentStopsNav, bookmarksNav, moreNav]
    }

    @objc public let mapController: MapViewController
    @objc public let recentStopsController: RecentStopsViewController
    @objc public let bookmarksController: BookmarksViewController
    @objc public let moreController: MoreViewController

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
