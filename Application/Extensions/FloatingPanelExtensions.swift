//
//  FloatingPanelExtensions.swift
//  OBANext
//
//  Created by Aaron Brethorst on 12/29/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import UIKit
import FloatingPanel

// MARK: -

public protocol FloatingPanelContainer: NSObjectProtocol, FloatingPanelControllerDelegate {

    var floatingToolbar: HoverBar { get }

    func setFloatingToolbarHidden(_ hidden: Bool, animated: Bool)

    var floatingPanelController: FloatingPanelController { get set }

    /// The currently visible child floating panel, if one exists.
    var childFloatingPanel: FloatingPanelController? { get set }

    var previousFloatingPanelPosition: FloatingPanelPosition { get set }

    func closePanel(containing contentController: UIViewController, model: AnyObject?)

    /// Provides an opportunity for the implementer to do additional cleanup related to `model` after its panel closes.
    /// For instance, it could remove overlays from a map.
    ///
    /// - Parameter model: The model object. Optional.
    func panelForModelDidClose(_ model: AnyObject?)

    /// Updates the contents of the toolbar with the items proferred up by `controller`. Pass `nil` to hide the toolbar.
    ///
    /// - Note: hides the toolbar if `controller.hasToolbarItems` is `false`.
    ///
    /// - Parameters:
    ///   - controller: Optional. The controller that will proffer up toolbar items.
    ///   - animated: Animate the toolbar transition, if relevant.
    func updateToolbar(with controller: UIViewController?, animated: Bool)
    
    /// Displays a view controller as a bottom-attached floating panel.
    ///
    /// - Parameters:
    ///   - contentController: The view controller that will be presented as a floating panel.
    ///   - scrollView: The view controller's scroll view, if one exists.
    ///   - animated: If the floating panel should be animated in to view.
    ///   - position: The desired position for the view controller that is presented.
    func presentFloatingPanel(contentController: UIViewController, scrollView: UIScrollView?, animated: Bool, position: FloatingPanelPosition)
}

public extension FloatingPanelContainer where Self: UIViewController {
    func setFloatingToolbarHidden(_ hidden: Bool, animated: Bool) {
        // short-circuit evaluation if we're not animated.
        guard animated else {
            floatingToolbar.isHidden = hidden
            floatingToolbar.alpha = 1.0
            return
        }

        guard hidden != floatingToolbar.isHidden else {
            return
        }

        if !hidden {
            floatingToolbar.alpha = 0.0
            floatingToolbar.isHidden = false
        }

        UIView.animate(withDuration: UIView.inheritedAnimationDuration, animations: { [weak floatingToolbar] in
            floatingToolbar?.alpha = hidden ? 0.0 : 1.0
        }, completion: { [weak floatingToolbar] _ in
            if hidden {
                floatingToolbar?.isHidden = true
            }
        })
    }

    /// Updates the contents of the toolbar with the items proferred up by `controller`. Pass `nil` to hide the toolbar.
    ///
    /// - Note: hides the toolbar if `controller.hasToolbarItems` is `false`.
    ///
    /// - Parameters:
    ///   - controller: Optional. The controller that will proffer up toolbar items.
    ///   - animated: Animate the toolbar transition, if relevant.
    func updateToolbar(with controller: UIViewController?, animated: Bool) {
        guard
            let items = controller?.toolbarItems,
            items.count > 0 else {
                setFloatingToolbarHidden(true, animated: animated)
                floatingToolbar.items = []
                return
        }

        setFloatingToolbarHidden(false, animated: animated)
        floatingToolbar.items = items
    }


    func closePanel(containing contentController: UIViewController, model: AnyObject?) {
        guard
            let childFloatingPanel = childFloatingPanel,
            childFloatingPanel.contentViewController == contentController
            else {
                return
        }

        updateToolbar(with: nil, animated: false)
        childFloatingPanel.removePanelFromParent(animated: true) { [weak self] in
            guard let self = self else {
                return
            }

            if self.childFloatingPanel == contentController {
                self.childFloatingPanel = nil
            }

            // Ensure that we never end up with the root floating
            // panel hidden after dismissing a child panel.
            let position = self.previousFloatingPanelPosition == .hidden ? .half : self.previousFloatingPanelPosition

            self.floatingPanelController.move(to: position, animated: true)
        }

        panelForModelDidClose(model)
    }

    func presentFloatingPanel(contentController: UIViewController, scrollView: UIScrollView?, animated: Bool, position: FloatingPanelPosition = .half) {
        // 1. Track state
        previousFloatingPanelPosition = floatingPanelController.position

        // 2. Create a new floating panel.
        // abxoxo
        let detailPanel = createFloatingPanelController(contentController: contentController, scrollView: scrollView)

        // 3. Display the new floating panel.
        detailPanel.addPanel(toParent: self, belowView: floatingToolbar, animated: animated)
        detailPanel.move(to: position, animated: animated) {
            // 5. Minimize the parent floating panel.
            self.floatingPanelController.move(to: .hidden, animated: animated)

            // 6. Configure the toolbar, if applicable.
            self.updateToolbar(with: contentController, animated: true)
        }

        // 4. If the contentController conforms to FloatingPanelContent,
        // which means it has a bottomScrollInset property, then set the
        // inset to be 40pt above the top of the hoverBar.
        if var panelContent = contentController as? FloatingPanelContent {
            let offset = floatingToolbar.frame.minY
            let controllerHeight = view.frame.height
            let padding: CGFloat = 40.0
            panelContent.bottomScrollInset += ((controllerHeight - offset) + padding)
        }

        childFloatingPanel = detailPanel
    }

    func floatingPanelDidChangePosition(_ vc: FloatingPanelController) {
        guard vc == childFloatingPanel else {
            return
        }

        let hidden = vc.position == .tip || vc.position == .hidden
        setFloatingToolbarHidden(hidden, animated: true)
    }

    func createFloatingPanelController(contentController: UIViewController, scrollView: UIScrollView?) -> FloatingPanelController {
        let fpc = FloatingPanelController(contentController: contentController, scrollView: scrollView)
        fpc.delegate = self
        fpc.contentInsetAdjustmentBehavior = .never
        fpc.backdropView.isHidden = true

        return fpc
    }
}

// MARK: - Extensions to FloatingPanel Library

extension FloatingPanelSurfaceView {

    /// Use this to properly inset a search bar or other similar views at the top of a floating panel,
    /// such that the height of the area above the grabber handle is the same as the height below.
    public static let searchBarEdgeInsets = NSDirectionalEdgeInsets(top: 7, leading: 0, bottom: 0, trailing: 0)

    /// Use this to properly inset a stack panel or other similar views at the top of a floating panel,
    /// such that the height of the area above the grabber handle is the same as the height below.
    public static let defaultTopEdgeInsets = NSDirectionalEdgeInsets(top: FloatingPanelSurfaceView.topGrabberBarHeight, leading: 0, bottom: 0, trailing: 0)


    private static let progressBarTag = 1111
    public func showProgressBar() {
        grabberHandle.isHidden = true
        progressBar.isHidden = false
    }

    public func hideProgressBar() {
        grabberHandle.isHidden = false
        progressBar.isHidden = true
    }

    public var progressBar: IndeterminateProgressView {
        if let v = viewWithTag(FloatingPanelSurfaceView.progressBarTag) as? IndeterminateProgressView {
            return v
        }

        let progressBar = IndeterminateProgressView(frame: CGRect(x: 0, y: FloatingPanelSurfaceView.topGrabberBarHeight / 2.0, width: self.frame.width, height: grabberHandle.frame.size.height))
        progressBar.backgroundColor = .clear
        progressBar.tag = FloatingPanelSurfaceView.progressBarTag
        progressBar.isHidden = true
        addSubview(progressBar)

        return progressBar
    }
}

extension FloatingPanelController {
    public convenience init(contentController: UIViewController, scrollView: UIScrollView?) {
        self.init()
        surfaceView.backgroundColor = .clear
        surfaceView.cornerRadius = 8.0
        surfaceView.shadowHidden = false
        set(contentViewController: contentController)
        if let scrollView = scrollView {
            track(scrollView: scrollView)
        }
    }
}

/// This protocol is implemented by floating panel child controllers.
public protocol FloatingPanelContent {
    func surfaceView() -> FloatingPanelSurfaceView?

    /// An inset value set by the presenting controller to indicate by
    /// how much this controller should inset its bottom content inset.
    var bottomScrollInset: CGFloat { get set }
}

extension FloatingPanelContent where Self: UIViewController {
    public func surfaceView() -> FloatingPanelSurfaceView? {
        guard let v = view.superview as? FloatingPanelSurfaceView else {
            return nil
        }

        return v
    }
}

