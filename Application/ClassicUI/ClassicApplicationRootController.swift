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

        super.init(nibName: nil, bundle: nil)

        self.viewControllers = [mapNav, recentStopsNav]
    }

    private let mapController: MapViewController
    private let recentStopsController: RecentStopsViewController

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
