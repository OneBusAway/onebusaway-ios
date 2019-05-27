//
//  Router.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 5/26/19.
//

import UIKit

/// Provides an standard interface for navigating between view controllers that works
/// regardless of how inter-controller navigation is designed to work in the app.
///
/// For example, this router can be used identically when the app is configured to
/// use floating panels or standard `UINavigationController` stacks.
///
public class ViewRouter: NSObject {
    private let application: Application
    
    public init(application: Application) {
        self.application = application
        super.init()
    }
    
    /// Navigates from `fromController` to `viewController`.
    ///
    /// - Parameters:
    ///   - viewController: The 'to' view controller.
    ///   - fromController: The 'from' view controller.
    public func navigate(to viewController: UIViewController, from fromController: UIViewController) {
        fromController.navigationController?.pushViewController(viewController, animated: true)
    }
    
    public func navigateTo(stopID: String, from fromController: UIViewController) {
        let stopController = StopViewController(application: application, stopID: stopID)
        navigate(to: stopController, from: fromController)
    }
    
    public func navigateTo(stop: Stop, from fromController: UIViewController) {
        navigateTo(stopID: stop.id, from: fromController)
    }
}
