//
//  Router.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 5/26/19.
//

import UIKit
import OBAKitCore

/// Provides an standard interface for navigating between view controllers that works
/// regardless of how inter-controller navigation is designed to work in the app.
///
/// For example, this router can be used identically when the app is configured to
/// use floating panels or standard `UINavigationController` stacks.
///
public class ViewRouter: NSObject, UINavigationControllerDelegate {
    private let application: Application

    public init(application: Application) {
        self.application = application
        super.init()
    }

    /// Modally presents the specified view controller.
    /// - Parameter presentedController: The modally-presented controller.
    /// - Parameter fromController: The controller that presents `presentedController`.
    /// - Parameter isModal: When running on iOS 13 and above, this is the value that will be set for
    ///                                    `presentedController.isModalInPresentation`, which controls whether
    ///                                    a modal view controller can be interactively dismissed by the user. Defaults
    ///                                    to `false`, mirroring iOS's behavior.
    public func present(
        _ presentedController: UIViewController,
        from fromController: UIViewController,
        isModal: Bool = false
    ) {
        if #available(iOS 13.0, *) {
            presentedController.isModalInPresentation = isModal
        }

        fromController.present(presentedController, animated: true, completion: nil)
    }

    /// Navigates from `fromController` to `viewController`.
    /// - Note: Sets `hidesBottomBarWhenPushed` to `true`for `viewController`.
    ///
    /// - Parameters:
    ///   - viewController: The 'to' view controller.
    ///   - fromController: The 'from' view controller.
    public func navigate(to viewController: UIViewController, from fromController: UIViewController) {
        assert(fromController.navigationController != nil)
        viewController.hidesBottomBarWhenPushed = true
        fromController.navigationController?.pushViewController(viewController, animated: true)
    }

    public func navigateTo(stop: Stop, from fromController: UIViewController, bookmark: Bookmark? = nil) {
        let stopController = StopViewController(application: application, stop: stop)
        stopController.bookmarkContext = bookmark
        navigate(to: stopController, from: fromController)
    }

    public func navigateTo(arrivalDeparture: ArrivalDeparture, from fromController: UIViewController) {
        let tripController = TripViewController(application: application, arrivalDeparture: arrivalDeparture)
        navigate(to: tripController, from: fromController)
    }

    // MARK: - Helpers

    /// Creates and configures a `UINavigationController` for the specified controller, setting some preferred options along the way.
    /// - Parameter controller: The `rootViewController` of the `UINavigationController`.
    /// - Parameter prefersLargeTitles: Controls the `prefersLargeTitle` setting of the navigation bar.
    public func buildNavigation(controller: UIViewController, prefersLargeTitles: Bool = false) -> UINavigationController {
        let navigation = UINavigationController(rootViewController: controller)
        navigation.navigationBar.prefersLargeTitles = prefersLargeTitles

        return navigation
    }
}
