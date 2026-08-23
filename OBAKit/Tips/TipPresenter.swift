//
//  TipPresenter.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 12/9/25.
//

import UIKit
import TipKit

/// Hosts a `TipUIView` for presentation as a popover.
///
/// This exists instead of `TipUIPopoverViewController` because, as of iOS 26,
/// that class's content view is never resized to fit the popover's content
/// area. The tip's content gets clipped out of the visible bubble, leaving an
/// empty popover. Hosting `TipUIView` ourselves and sizing the popover via
/// `preferredContentSize` sidesteps the broken system controller.
class TipHostingViewController: UIViewController {
    private let tipView: TipUIView

    init(tip: any Tip) {
        self.tipView = TipUIView(tip)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // TipUIView draws its own rounded-rect background, which looks doubled
        // inside the popover bubble.
        tipView.backgroundColor = .clear
        tipView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tipView)

        NSLayoutConstraint.activate([
            tipView.topAnchor.constraint(equalTo: view.topAnchor),
            tipView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tipView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tipView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        preferredContentSize = tipView.systemLayoutSizeFitting(
            CGSize(width: 320, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
    }
}

/// Simplifies the process of showing a `TipKit` `Tip` within `UIKit`.
///
/// Call `showIfNeeded(in:sourceItem:)` from `viewDidAppear` with the view the tip
/// should point at, and `stop()` from `viewWillDisappear`.
class TipPresenter: NSObject, UIPopoverPresentationControllerDelegate {
    private let tip: any Tip
    private var tipObservationTask: Task<Void, Never>?
    private var tipViewController: TipHostingViewController?

    /// Creates the TipPresenter
    /// - Parameter tip: The tip object that will be presented.
    init(tip: any Tip) {
        self.tip = tip
    }

    /// You must call this from `UIViewController.viewWillDisappear()`.
    func stop() {
        tipObservationTask?.cancel()
        tipObservationTask = nil

        // Take the popover with the screen it belongs to. Merely forgetting it
        // would strand a visible bubble anchored to a view the rider has left,
        // and `tipWasDismissedByUser()` would then no-op when it finally closed,
        // so TipKit would never learn the tip had been shown and dismissed.
        tipViewController?.dismiss(animated: false)
        tipViewController = nil
    }

    /// Presents the tip from `presenter`, if TipKit's conditions are met.
    ///
    /// Safe to call repeatedly — the observation is started at most once, and is
    /// skipped entirely once the tip has been invalidated.
    ///
    /// - Parameters:
    ///   - presenter: The view controller that presents (and dismisses) the tip popover. Held weakly.
    ///   - sourceItem: The `UIView`/`UIBarButtonItem`/`UITabBarItem` the tip points at.
    ///   - sourceRect: The frame within the sourceItem. Only needed for `UIView` sources; `UIBarButtonItem` and `UITabBarItem` handle positioning automatically.
    ///   - animated: Whether the popover animates in and out.
    func showIfNeeded(
        in presenter: UIViewController,
        sourceItem: (any UIPopoverPresentationControllerSourceItem),
        sourceRect: CGRect? = nil,
        animated: Bool = true
    ) {
        // An invalidated tip can only ever report `false`, so subscribing again
        // would rebuild a datastore observation on every appearance for the rest
        // of the session and never present anything.
        if case .invalidated = tip.status { return }

        guard tipObservationTask == nil else { return }

        tipObservationTask = Task { @MainActor [weak presenter] in
            for await shouldDisplay in tip.shouldDisplayUpdates {
                guard let presenter else { return }

                if shouldDisplay {
                    // Nothing may be presented already: a tip popover that lands
                    // on top of a stop sheet or another tip either fails outright
                    // or steals the screen from something the rider asked for.
                    guard tipViewController == nil, presenter.presentedViewController == nil else { continue }

                    let hostingController = TipHostingViewController(tip: tip)
                    hostingController.modalPresentationStyle = .popover

                    // Configure popover presentation controller
                    if let popover = hostingController.popoverPresentationController {
                        popover.sourceItem = sourceItem
                        if let sourceRect {
                            popover.sourceRect = sourceRect
                        }
                        popover.delegate = self
                    }

                    presenter.present(hostingController, animated: animated)
                    tipViewController = hostingController
                }
                else if let tipViewController {
                    // Only ever dismiss the controller *this* presenter put up.
                    // Two presenters can share a screen — the map's layer tip and
                    // the floating panel's trip-planner tip — so acting on
                    // `presenter.presentedViewController` would let whichever tip
                    // goes ineligible first tear down the other one's popover.
                    tipViewController.dismiss(animated: animated)
                    self.tipViewController = nil
                }
            }
        }
    }

    /// Ensures that the tip is presented in an appropriate style on an iPhone.
    func adaptivePresentationStyle(
        for controller: UIPresentationController,
        traitCollection: UITraitCollection
    ) -> UIModalPresentationStyle {
        // Return .none to prevent the popover from adapting to a sheet on iPhone
        return .none
    }

    /// Called when the user dismisses the popover by tapping outside of it.
    /// Without this, TipKit never learns the tip was dismissed, and it will
    /// reappear on every subsequent launch.
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        tipWasDismissedByUser()
    }

    func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {
        tipWasDismissedByUser()
    }

    private func tipWasDismissedByUser() {
        guard tipViewController != nil else { return }
        tip.invalidate(reason: .tipClosed)
        tipViewController = nil
    }
}
