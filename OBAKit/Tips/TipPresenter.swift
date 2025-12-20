//
//  TipPresenter.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 12/9/25.
//

import UIKit
import TipKit

/// Simplifies the process of showing a `TipKit` `Tip` within `UIKit`.
///
/// Call `showIfNeeded()` with a `sourceItem`, which is the view to attach the tip to,
/// `present`, which simply calls `UIViewController.present()`,  and
/// `dismiss`, which 
class TipPresenter: NSObject, UIPopoverPresentationControllerDelegate {
    private let tip: any Tip
    private var tipObservationTask: Task<Void, Never>?
    private var tipPopoverController: TipUIPopoverViewController?

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
                    let popoverController = TipUIPopoverViewController(tip, sourceItem: sourceItem)
                    popoverController.modalPresentationStyle = .popover

                    // Configure popover presentation controller
                    if let popover = popoverController.popoverPresentationController {
                        popover.sourceItem = sourceItem
                        if let sourceRect {
                            popover.sourceRect = sourceRect
                        }
                        popover.delegate = self
                    }

                    present(popoverController)
                    tipPopoverController = popoverController
                }
                else {
                    let presentedController = presentedController()

                    if let presentedController, presentedController is TipUIPopoverViewController {
                        dismiss(presentedController)
                        tipPopoverController = nil
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
}
