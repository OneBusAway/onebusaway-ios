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
/// Call `showIfNeeded()` with a `sourceItem`, which is the view to attach the tip to,
/// `present`, which simply calls `UIViewController.present()`, and
/// `dismiss`, which calls `dismiss()` on the presented view controller.
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
    }

    /// Presents the tip, if its internal conditions are met.
    /// - Parameters:
    ///   - sourceItem: The `UIView`/`UIBarButtonItem`/`UITabBarItem` that will be the presented source of the tip.
    ///   - sourceRect: The frame within the sourceItem. Only needed for `UIView` sources; `UIBarButtonItem` and `UITabBarItem` handle positioning automatically.
    ///   - present: A handler that is responsible for presenting  the `UIViewController` parameter  via `UIViewController.present()`.
    ///   - presentedController: A handler that is responsible for returning `UIViewController.presentedViewController`
    ///   - dismiss: A handler that is responsible for calling `dismiss()` on the `UIViewController` parameter.
    func showIfNeeded(
        sourceItem: (any UIPopoverPresentationControllerSourceItem),
        sourceRect: CGRect? = nil,
        present: @escaping (UIViewController) -> Void,
        presentedController: @escaping () -> (UIViewController?),
        dismiss: @escaping (UIViewController) -> Void
    ) {
        tipObservationTask = tipObservationTask ?? Task { @MainActor in
            for await shouldDisplay in tip.shouldDisplayUpdates {
                if shouldDisplay {
                    guard tipViewController == nil else { continue }

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

                    present(hostingController)
                    tipViewController = hostingController
                }
                else {
                    let presentedController = presentedController()

                    if let presentedController, presentedController is TipHostingViewController {
                        dismiss(presentedController)
                        tipViewController = nil
                    }
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
