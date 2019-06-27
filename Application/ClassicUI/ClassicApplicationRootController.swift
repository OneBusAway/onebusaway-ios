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
        let mapNav = UINavigationController(rootViewController: self.mapController)

        self.recentStopsController = RecentStopsViewController(application: application)
        let recentStopsNav = UINavigationController(rootViewController: self.recentStopsController)

        self.bookmarksController = BookmarksViewController(application: application)
        let bookmarksNav = UINavigationController(rootViewController: self.bookmarksController)

        self.moreController = MoreViewController(application: application)
        let moreNav = UINavigationController(rootViewController: self.moreController)

        super.init(nibName: nil, bundle: nil)

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
