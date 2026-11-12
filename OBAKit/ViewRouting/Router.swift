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

    private let registeredRootControllers = NSHashTable<ClassicApplicationRootController>.weakObjects()
    private let registeredMapPanelRootControllers = NSHashTable<MapPanelRootController>.weakObjects()

    func register(rootController: ClassicApplicationRootController) {
        registeredRootControllers.add(rootController)
    }

    /// Registers an active `MapPanelRootController` with the router.
    ///
    /// - Parameter mapPanelRootController: The map panel root controller to register.
    func register(mapPanelRootController: MapPanelRootController) {
        registeredMapPanelRootControllers.add(mapPanelRootController)
    }

    /// Resolves the active or context-specific `MapPanelRootController`.
    ///
    /// Symmetrical to `rootController(from:)`, dynamically resolves the map panel
    /// root controller from calling context, active foreground window scenes, or connected scenes.
    ///
    /// - Parameter context: An optional view controller to search ancestor/window hierarchies from.
    /// - Returns: The resolved `MapPanelRootController` or `nil` if not running in map-panel mode.
    public func mapPanelRootController(from context: UIViewController? = nil) -> MapPanelRootController? {
        if let context = context {
            if let mapPanel = findMapPanelRoot(from: context) {
                return mapPanel
            }
            if let windowScene = context.viewIfLoaded?.window?.windowScene {
                return findMapPanelRoot(in: windowScene, preferringKeyWindow: false)
            }
        }

        // Check active foreground window scenes first
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene,
                  windowScene.activationState == .foregroundActive else { continue }
            if let mapPanel = findMapPanelRoot(in: windowScene) {
                return mapPanel
            }
        }

        // Check any connected window scene
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            if let mapPanel = findMapPanelRoot(in: windowScene) {
                return mapPanel
            }
        }

        // Fallback for tests or environments without window scenes
        for root in registeredMapPanelRootControllers.allObjects where root.viewIfLoaded?.window?.isKeyWindow == true {
            return root
        }
        return registeredMapPanelRootControllers.allObjects.first
    }

    /// Backwards-compatible computed accessor that resolves the map panel root controller without context.
    public var mapPanelRootController: MapPanelRootController? {
        mapPanelRootController(from: nil)
    }

    /// Resolves the active or context-specific `ClassicApplicationRootController`.
    ///
    /// Rather than holding a single strong reference to a root controller (which would
    /// overwrite across windows and leak closed windows in multi-window environments),
    /// this dynamically resolves the root controller from the calling context, active
    /// window scene, or connected scenes.
    public func rootController(from context: UIViewController? = nil) -> ClassicApplicationRootController? {
        if let context = context {
            if let classic = findClassicRoot(from: context) {
                return classic
            }
            if let windowScene = context.viewIfLoaded?.window?.windowScene {
                return findClassicRoot(in: windowScene, preferringKeyWindow: false)
            }
        }

        // Check active foreground window scenes first
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene,
                  windowScene.activationState == .foregroundActive else { continue }
            if let classic = findClassicRoot(in: windowScene) {
                return classic
            }
        }

        // Check any connected window scene
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            if let classic = findClassicRoot(in: windowScene) {
                return classic
            }
        }

        // Fallback for tests or environments without window scenes:
        // check registered controllers (held weakly).
        for root in registeredRootControllers.allObjects where root.viewIfLoaded?.window?.isKeyWindow == true {
            return root
        }
        return registeredRootControllers.allObjects.first
    }

    /// Backwards-compatible computed accessor that resolves the root controller without context.
    public var rootController: ClassicApplicationRootController? {
        rootController(from: nil)
    }

    private func findClassicRoot(from context: UIViewController?) -> ClassicApplicationRootController? {
        guard let context = context else { return nil }
        if let classic = context as? ClassicApplicationRootController {
            return classic
        }
        if let classic = context.tabBarController as? ClassicApplicationRootController {
            return classic
        }
        if let window = context.viewIfLoaded?.window,
           let classic = findClassicRoot(in: window.rootViewController) {
            return classic
        }
        if let nav = context.navigationController,
           let classic = findClassicRoot(from: nav) {
            return classic
        }
        if let presenting = context.presentingViewController,
           let classic = findClassicRoot(from: presenting) {
            return classic
        }
        return nil
    }

    /// Searches `windowScene`'s windows, starting with its key window unless `preferringKeyWindow` is `false`.
    private func findClassicRoot(in windowScene: UIWindowScene, preferringKeyWindow: Bool = true) -> ClassicApplicationRootController? {
        if preferringKeyWindow,
           let keyWindow = windowScene.keyWindow,
           let classic = findClassicRoot(in: keyWindow.rootViewController) {
            return classic
        }
        for window in windowScene.windows {
            if let classic = findClassicRoot(in: window.rootViewController) {
                return classic
            }
        }
        return nil
    }

    private func findClassicRoot(in viewController: UIViewController?) -> ClassicApplicationRootController? {
        guard let viewController = viewController else { return nil }
        if let classic = viewController as? ClassicApplicationRootController {
            return classic
        }
        if let presented = viewController.presentedViewController,
           let classic = findClassicRoot(in: presented) {
            return classic
        }
        for child in viewController.children {
            if let classic = findClassicRoot(in: child) {
                return classic
            }
        }
        return nil
    }

    private func findMapPanelRoot(from context: UIViewController?) -> MapPanelRootController? {
        guard let context = context else { return nil }
        if let mapPanel = context as? MapPanelRootController {
            return mapPanel
        }
        if let window = context.viewIfLoaded?.window,
           let mapPanel = findMapPanelRoot(in: window.rootViewController) {
            return mapPanel
        }
        if let nav = context.navigationController,
           let mapPanel = findMapPanelRoot(from: nav) {
            return mapPanel
        }
        if let presenting = context.presentingViewController,
           let mapPanel = findMapPanelRoot(from: presenting) {
            return mapPanel
        }
        return nil
    }

    private func findMapPanelRoot(in windowScene: UIWindowScene, preferringKeyWindow: Bool = true) -> MapPanelRootController? {
        if preferringKeyWindow,
           let keyWindow = windowScene.keyWindow,
           let mapPanel = findMapPanelRoot(in: keyWindow.rootViewController) {
            return mapPanel
        }
        for window in windowScene.windows {
            if let mapPanel = findMapPanelRoot(in: window.rootViewController) {
                return mapPanel
            }
        }
        return nil
    }

    private func findMapPanelRoot(in viewController: UIViewController?) -> MapPanelRootController? {
        guard let viewController = viewController else { return nil }
        if let mapPanel = viewController as? MapPanelRootController {
            return mapPanel
        }
        if let presented = viewController.presentedViewController,
           let mapPanel = findMapPanelRoot(in: presented) {
            return mapPanel
        }
        for child in viewController.children {
            if let mapPanel = findMapPanelRoot(in: child) {
                return mapPanel
            }
        }
        return nil
    }

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

    public func navigateTo(stop: Stop, from fromController: UIViewController, bookmark: Bookmark? = nil, transferContext: TransferContext? = nil) {
        guard shouldNavigate(from: fromController, to: .stop(stop)) else { return }
        if fromController.navigationController == nil, let panel = mapPanelRootController(from: fromController) {
            panel.navigate(to: .stopDetails(stopID: stop.id), popToRootFirst: false)
            return
        }
        navigate(to: makeStopController(stop: stop, bookmark: bookmark, transferContext: transferContext), from: fromController)
    }

    public func navigateTo(stopID: StopID, from fromController: UIViewController, transferContext: TransferContext? = nil) {
        guard shouldNavigate(from: fromController, to: .stopID(stopID)) else { return }
        if fromController.navigationController == nil, let panel = mapPanelRootController(from: fromController) {
            panel.navigate(to: .stopDetails(stopID: stopID), popToRootFirst: false)
            return
        }
        navigate(to: makeStopController(stopID: stopID, transferContext: transferContext), from: fromController)
    }

    /// Builds the Stop screen. All stop navigation and long-press previews construct the
    /// controller through these factories, so the transfer context is gated the same way on
    /// every path.
    ///
    /// - Parameter showToolbarOnBottom: Pass `true` when the caller will present the result as a
    ///   sheet rather than push it, which swaps the page's dark map header for a light one and
    ///   moves its chrome into a bottom toolbar. The transfer context is gated by
    ///   `displayedTransferContext`, and drives trip highlighting on the page.
    public func makeStopController(stop: Stop, bookmark: Bookmark? = nil, transferContext: TransferContext? = nil, showToolbarOnBottom: Bool = false) -> UIViewController {
        let stopController = StopPageViewController(application: application, stop: stop, showToolbarOnBottom: showToolbarOnBottom)
        stopController.bookmarkContext = bookmark
        stopController.transferContext = application.userDataStore.displayedTransferContext(transferContext)
        return stopController
    }

    public func makeStopController(stopID: StopID, transferContext: TransferContext? = nil, showToolbarOnBottom: Bool = false) -> UIViewController {
        let stopController = StopPageViewController(application: application, stopID: stopID, showToolbarOnBottom: showToolbarOnBottom)
        stopController.transferContext = application.userDataStore.displayedTransferContext(transferContext)
        return stopController
    }

    /// - Parameter destinationStopID: Where the sharer said they will step off,
    ///   when this came from a shared trip link that named one. See #449.
    public func navigateTo(
        arrivalDeparture: ArrivalDeparture,
        from fromController: UIViewController,
        destinationStopID: StopID? = nil
    ) {
        guard shouldNavigate(from: fromController, to: .arrivalDeparture(arrivalDeparture)) else { return }
        if fromController.navigationController == nil, let panel = mapPanelRootController(from: fromController) {
            panel.navigate(
                to: .tripDetails(
                    TripConvertible(arrivalDeparture: arrivalDeparture),
                    destinationStopID: destinationStopID
                ),
                popToRootFirst: false
            )
            return
        }
        let tripController = makeTripController(
            tripConvertible: TripConvertible(arrivalDeparture: arrivalDeparture),
            destinationStopID: destinationStopID
        )
        navigate(to: tripController, from: fromController)
    }

    /// Builds the trip screen for every surface that pushes one full-screen, or
    /// previews one: the trip page over a map of its own. The map tab's stop
    /// sheet and the map panel host the page over their own map instead.
    ///
    /// - Parameter destinationStopID: Where the sharer said they will step off,
    ///   when this came from a shared trip link that named one. See #449.
    func makeTripController(tripConvertible: TripConvertible, destinationStopID: StopID? = nil) -> TripMapHostViewController {
        TripMapHostViewController(
            application: application,
            tripConvertible: tripConvertible,
            destinationStopID: destinationStopID
        )
    }

    /// Navigates to a top-level tab page in classic mode, or to the corresponding
    /// sheet route in map-panel mode.
    ///
    /// - Parameters:
    ///   - page: The root page destination to navigate to.
    ///   - context: Optional caller view controller providing scene/window context.
    public func rootNavigateTo(page: ClassicApplicationRootController.Page, from context: UIViewController? = nil) {
        if let mapPanel = mapPanelRootController(from: context) {
            switch page {
            case .map:
                mapPanel.navigate(to: .home, popToRootFirst: true)
            case .recentStops:
                mapPanel.navigate(to: .recentStopsAll, popToRootFirst: false)
            case .bookmarks:
                mapPanel.navigate(to: .bookmarksAll, popToRootFirst: false)
            case .more:
                mapPanel.navigate(to: .more, popToRootFirst: false)
            }
            return
        }

        guard let rootController = self.rootController(from: context) else {
            Logger.error("rootNavigateTo(page: \(page)) dropped: no root controller found")
            return
        }
        rootController.navigate(to: page)
    }

    private func pushTarget(from context: UIViewController?) -> UIViewController? {
        if let target = context, target.navigationController != nil {
            return target
        }
        if let nav = context as? UINavigationController, let visible = nav.visibleViewController ?? nav.topViewController, visible.navigationController != nil {
            return visible
        }
        return nil
    }

    /// Navigates to the specified `AppSheetRoute` in the modern map-panel experience,
    /// or translates the route to its classic navigation counterpart when classic mode is active.
    ///
    /// - Parameters:
    ///   - route: The destination sheet route to display.
    ///   - context: Optional caller view controller providing scene/window context.
    ///   - popToRootFirst: When `true`, resets the sheet stack or tab navigation before presenting.
    /// - Returns: `true` if navigation was handled; `false` otherwise.
    @discardableResult
    func navigate(
        to route: AppSheetRoute,
        from context: UIViewController? = nil,
        popToRootFirst: Bool = false
    ) -> Bool {
        if let mapPanel = mapPanelRootController(from: context) {
            mapPanel.navigate(to: route, popToRootFirst: popToRootFirst)
            return true
        }

        switch route {
        case .home:
            rootNavigateTo(page: .map, from: context)
            return true
        case .recentStopsAll:
            rootNavigateTo(page: .recentStops, from: context)
            return true
        case .bookmarksAll:
            rootNavigateTo(page: .bookmarks, from: context)
            return true
        case .more:
            rootNavigateTo(page: .more, from: context)
            return true
        case .stopDetails(let stopID):
            if let target = pushTarget(from: context) {
                navigateTo(stopID: stopID, from: target)
                return true
            }
            application.pushStopFromOutside(stopID)
            return true
        case .tripDetails(let convertible, let destinationStopID):
            let tripVC = makeTripController(tripConvertible: convertible, destinationStopID: destinationStopID)
            if let target = pushTarget(from: context) {
                navigate(to: tripVC, from: target)
                return true
            }
            application.withPushableTopViewController { [weak self] from in
                self?.navigate(to: tripVC, from: from)
            }
            return true
        default:
            Logger.warn("AppSheetRoute \(route) has no classic mode equivalent; dropped.")
            return false
        }
    }

    public func navigateTo(alert: TransitAlertViewModel, locale: Locale = .current, from fromController: UIViewController) {
        guard shouldNavigate(from: fromController, to: .transitAlert(alert)) else { return }

        let view = TransitAlertDetailViewController(alert, locale: locale)
        let navigationController = UINavigationController(rootViewController: view)
        present(navigationController, from: fromController)
    }

    /// Pushes the on-demand service page.
    public func navigateTo(onDemandService service: OnDemandService, from fromController: UIViewController) {
        navigate(to: OnDemandServiceViewController(application: application, service: service), from: fromController)
    }

    /// Presents the route picker modal, then navigates to the current trip flow.
    ///
    /// - Parameter fromController: The view controller presenting the modal.
    public func navigateToCurrentTrip(from fromController: UIViewController) {
        let picker = RoutePickerViewController(application: application, delegate: self)
        let navigation = buildNavigation(controller: picker)
        present(navigation, from: fromController)
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

// MARK: - RoutePickerDelegate

extension ViewRouter: RoutePickerDelegate {
    func routePicker(_ picker: RoutePickerViewController, didSelectRoute route: Route) {
        guard let navigation = picker.navigationController else { return }

        let currentTripController = CurrentTripViewController(application: application, route: route)
        navigation.pushViewController(currentTripController, animated: true)
    }
}
