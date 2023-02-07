//
//  Router.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore
import SafariServices

/// Provides an standard interface for navigating between view controllers that works
/// regardless of how inter-controller navigation is designed to work in the app.
///
/// For example, this router can be used identically when the app is configured to
/// use floating panels or standard `UINavigationController` stacks.
///
@MainActor
public class ViewRouter: NSObject, UINavigationControllerDelegate {
    public enum NavigationDestination {
        case stop(Stop)
        case stopID(String)
        case arrivalDeparture(ArrivalDeparture)
        case transitAlert(TransitAlertViewModel)
    }

    private let application: Application

    var rootController: ClassicApplicationRootController?

    public init(application: Application) {
        self.application = application
        super.init()
    }

    /// Modally presents the specified view controller.
    /// - Parameters:
    ///   - presentedController: The modally-presented controller.
    ///   - fromController: The controller that presents `presentedController`.
    ///   - isModal: When running on iOS 13 and above, this is the value that will be set for `presentedController.isModalInPresentation`,
    ///              which controls whether a modal view controller can be interactively dismissed by the user. Defaults to `false`, mirroring iOS's behavior.
    ///   - isPopover: if `presentedController` should be displayed as a popover. If this is true, then the next two parameters must also be set.
    ///   - popoverSourceView: Used to set the `sourceView` property of the popover presentation controller.
    ///   - popoverSourceFrame: Used to set the `sourceRect` property of the popover presentation controller.
    ///   - popoverBarButtonItem: Used to set the `sourceRect` property of the popover presentation controller.
    public func present(
        _ presentedController: UIViewController,
        from fromController: UIViewController,
        isModal: Bool = false,
        isPopover: Bool = false,
        popoverSourceView: UIView? = nil,
        popoverSourceFrame: CGRect? = nil,
        popoverBarButtonItem: UIBarButtonItem? = nil
    ) {
        presentedController.isModalInPresentation = isModal
        if isPopover, let popover = presentedController.popoverPresentationController {
            if let popoverSourceFrame = popoverSourceFrame {
                popover.sourceRect = popoverSourceFrame
            }

            popover.sourceView = popoverSourceView
            popover.barButtonItem = popoverBarButtonItem
            presentedController.modalPresentationStyle = .popover
        }

        fromController.present(presentedController, animated: true, completion: nil)
    }

    /// Navigates from `fromController` to `viewController`.
    /// - Note: Sets `hidesBottomBarWhenPushed` to `true`for `viewController`.
    ///
    /// - Parameters:
    ///   - viewController: The 'to' view controller.
    ///   - fromController: The 'from' view controller.
    ///   - animated: Is the transition animated or not.
    public func navigate(to viewController: UIViewController, from fromController: UIViewController, animated: Bool = true) {
        assert(fromController.navigationController != nil)
        fromController.navigationController?.pushViewController(viewController, animated: animated)
    }

    public func navigateTo(stop: Stop, from fromController: UIViewController, bookmark: Bookmark? = nil) {
        guard shouldNavigate(from: fromController, to: .stop(stop)) else { return }
        let stopController = StopViewController(application: application, stop: stop)
        stopController.bookmarkContext = bookmark
        navigate(to: stopController, from: fromController)
    }

    public func navigateTo(stopID: StopID, from fromController: UIViewController) {
        guard shouldNavigate(from: fromController, to: .stopID(stopID)) else { return }
        let stopController = StopViewController(application: application, stopID: stopID)
        navigate(to: stopController, from: fromController)
    }

    public func navigateTo(arrivalDeparture: ArrivalDeparture, from fromController: UIViewController) {
        guard shouldNavigate(from: fromController, to: .arrivalDeparture(arrivalDeparture)) else { return }
        let tripController = TripViewController(application: application, arrivalDeparture: arrivalDeparture)
        navigate(to: tripController, from: fromController)
    }

    public func rootNavigateTo(page: ClassicApplicationRootController.Page) {
        guard let rootController = self.rootController else { return }
        rootController.navigate(to: page)
    }

    public func navigateTo(alert: TransitAlertViewModel, locale: Locale = .current, from fromController: UIViewController) {
        guard shouldNavigate(from: fromController, to: .transitAlert(alert)) else { return }

        if let url = alert.url(forLocale: locale) {
            let safari = SFSafariViewController(url: url)
            present(safari, from: fromController, isModal: true)
        } else {
            let view = TransitAlertDetailViewController(alert)
            present(view, from: fromController)
        }
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

    /// Checks if the origin view controller wants to override the navigation behavior.
    private func shouldNavigate(from fromController: UIViewController, to destination: NavigationDestination) -> Bool {
        guard let routerDelegate = fromController as? ViewRouterDelegate else { return true }
        return routerDelegate.shouldNavigate(to: destination)
    }
}
