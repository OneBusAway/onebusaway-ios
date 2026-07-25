//
//  StopSheetPresenter.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import FloatingPanel
import UIKit
import OBAKitCore

/// Presents the redesigned Stop page as a half-detent sheet over the map, replacing the
/// push that the legacy `StopViewController` still uses.
///
/// The content controller is wrapped in a `UINavigationController` so that outbound navigation,
/// which runs through `ViewRouter.navigate(to:from:)` and asserts on a nil `navigationController`,
/// has somewhere to go: trip, alert, and bookmark-editor screens push *inside* the sheet rather
/// than replacing it. The bar itself is hidden while the stop page is on top — its chrome lives
/// in a bottom toolbar and its own header — and comes back for whatever gets pushed.
///
/// The presenter is deliberately ignorant of the map: it takes a dismissal handler per
/// presentation instead of a map view, so the caller decides what cleanup (annotation
/// deselection) means and this type stays testable without MapKit.
@MainActor
final class StopSheetPresenter: NSObject {

    /// Top inset for the content view, leaving room for the grabber above the navigation bar.
    /// `nonisolated` so `StopSheetLayout` can subtract it from a detent's budget.
    nonisolated fileprivate static let grabberClearance: CGFloat = 16.0

    private var panel: FloatingPanelController?
    private var navigation: UINavigationController?

    /// The tab bar controller whose bar is hidden for the current presentation. Non-nil only
    /// while a sheet is onscreen, so the bar can be put back exactly once.
    private var hostTabBarController: UITabBarController?

    /// Cleanup for the presentation currently onscreen. Held alongside the panel rather than
    /// as a settable property so that replacing one sheet with another fires the *outgoing*
    /// presentation's handler — assigning a new handler first would deselect the wrong
    /// annotation.
    private var dismissHandler: (() -> Void)?

    var isPresenting: Bool {
        panel != nil
    }

    // MARK: - Presentation

    /// Presents `contentController` in a half-detent panel added to `parent`.
    ///
    /// Any sheet already onscreen is torn down first — the HIG is explicit that only one sheet
    /// shows at a time, and the map has several things competing for this space.
    ///
    /// - Parameters:
    ///   - contentController: The stop page to show. Wrapped in a navigation controller here.
    ///   - parent: The view controller to add the panel to.
    ///   - onDismiss: Run once this presentation leaves the screen, however it leaves.
    func present(_ contentController: UIViewController, from parent: UIViewController, onDismiss: @escaping () -> Void) {
        // Swapping one stop for another leaves the tab bar hidden throughout: restoring it here
        // would flash it back into place for a turn, behind the incoming sheet.
        tearDown(animated: false, restoringTabBar: false)

        let navigation = UINavigationController(rootViewController: contentController)
        navigation.delegate = self
        configureNavigationBar(navigation.navigationBar)
        // Seeded here as well as in `willShow` so the bar is already gone on the first layout
        // pass; letting the delegate callback do it alone flashes a bar's worth of empty space
        // above the header as the sheet slides up.
        navigation.setNavigationBarHidden(hidesNavigationBar(for: contentController), animated: false)

        let panel = FloatingPanelController(delegate: self)
        panel.set(contentViewController: navigation)
        panel.isRemovalInteractionEnabled = false

        // The default `.static` mode gives the content view a constant height — the height of the
        // *most expanded* detent — and slides it. At `.half` that puts the content's bottom edge
        // roughly a full detent below the screen, which silently swallows anything anchored
        // there: the stop page's bottom toolbar was only visible when the sheet happened to be
        // at `.full`. `.fitToBounds` resizes the content to the surface's visible bounds instead,
        // so the toolbar sits on the screen's bottom edge at every detent.
        panel.contentMode = .fitToBounds

        // Hands the tracked scroll view's content insets back to whoever owns it — here, the
        // SwiftUI `List`. The default `.always` takes them over three different ways:
        // `track(scrollView:)` forces the scroll view's own `contentInsetAdjustmentBehavior` to
        // `.never`, and both `adjustScrollContentInsetIfNeeded()` and every layout pass then
        // assign `contentInset` outright (top: 0 for a bottom-positioned panel). That wipes the
        // top inset `safeAreaInset(edge: .top)` installs for the stop page's header, leaving the
        // mode toggle and the first departure stranded underneath it. `.always` exists to keep
        // content visible at intermediate detents under `.static` sizing, which `.fitToBounds`
        // already handles by resizing the content view to the surface's visible bounds.
        panel.contentInsetAdjustmentBehavior = .never

        let appearance = SurfaceAppearance()
        appearance.cornerRadius = ThemeMetrics.cornerRadius
        // Unlike the map drawer — whose content controller paints its own background — the
        // navigation controller here is inset by `grabberClearance`, so the surface itself has
        // to fill the strip behind the grabber.
        appearance.backgroundColor = .systemBackground
        panel.surfaceView.appearance = appearance
        panel.surfaceView.contentPadding = UIEdgeInsets(top: Self.grabberClearance, left: 0, bottom: 0, right: 0)

        self.panel = panel
        self.navigation = navigation
        self.dismissHandler = onDismiss
        self.hostTabBarController = parent.tabBarController

        // Seeded from the parent's traits rather than left to `floatingPanel(_:layoutFor:)`
        // alone: that delegate callback runs during `FloatingPanelController.init`, before the
        // panel is in a hierarchy, so a rider running a large content size category would get a
        // `.tip` sized for the default one until the next trait change.
        panel.layout = StopSheetLayout(traitCollection: parent.traitCollection)

        // `animated` defaults to `false`, which makes the sheet pop into place fully formed. A
        // fresh controller's state is `.hidden`, so passing `true` slides it up from offscreen
        // the way a sheet is expected to arrive.
        panel.addPanel(toParent: parent, animated: true)
        setHostTabBarHidden(true, animated: true)

        // `navigationController(_:didShow:)` covers every push and pop, but is not guaranteed to
        // fire for the root controller before the panel is onscreen, so seed tracking here too.
        // `trackScrollView(in:)` untracks first, making the overlap harmless.
        trackScrollView(in: contentController)
    }

    /// Tears down the sheet if one is showing, running its dismissal handler and putting the tab
    /// bar back.
    func dismiss(animated: Bool = true) {
        tearDown(animated: animated, restoringTabBar: true)
    }

    /// Releases the current presentation and detaches its panel from the view hierarchy.
    ///
    /// Detaches by way of `hide` rather than `removePanelFromParent` on purpose: the latter
    /// fires `floatingPanelDidRemove`, which would re-enter this method.
    private func tearDown(animated: Bool, restoringTabBar: Bool) {
        // An animated teardown holds the tab bar back until the sheet has gone; see
        // `restoreDeferredTabBar()`.
        guard let panel = releaseCurrentPresentation(restoringTabBar: restoringTabBar && !animated) else { return }

        panel.willMove(toParent: nil)

        let detach = {
            panel.view.removeFromSuperview()
            panel.removeFromParent()
        }

        guard animated else {
            panel.hide(animated: false, completion: detach)
            return
        }

        slideAway(panel) { [weak self] in
            // Leaves the panel at the hidden anchor before it's discarded, so nothing observes a
            // sheet that is offscreen by transform but still `.half` by state.
            panel.hide(animated: false, completion: detach)

            if restoringTabBar {
                self?.restoreDeferredTabBar()
            }
        }
    }

    /// Slides the sheet off the bottom edge of the screen, then hands back for teardown.
    ///
    /// FloatingPanel's own `hide(animated:)` animates the surface's *layout*, and under
    /// `.fitToBounds` that isn't a slide at all: the hidden anchor drives the surface's top edge
    /// down to the bottom of the screen while the fit-to-bounds constraint goes on holding its
    /// bottom edge there, so the sheet collapses in place instead of travelling. The SwiftUI page
    /// inside is resized on every frame of that collapse — the rider watches the stop page fold
    /// into a strip of clipped header over the toolbar, above a band of bare surface.
    ///
    /// Constraining the content's height to fight the collapse only moves the problem: the
    /// surface's position constraints are `.defaultHigh` at both edges, so a required height that
    /// neither of them can satisfy leaves the solver splitting the difference — at `.half`,
    /// visibly hauling the sheet up the screen before it drops. A transform sidesteps the layout
    /// system entirely: the whole sheet travels as one piece, at a fixed size, with no layout
    /// pass to re-lay the page out.
    private func slideAway(_ panel: FloatingPanelController, completion: @escaping () -> Void) {
        let surface = panel.surfaceView
        let distance = panel.view.bounds.maxY - surface.frame.minY

        guard distance > 0 else {
            completion()
            return
        }

        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
            surface.transform = CGAffineTransform(translationX: 0, y: distance)
            // The backdrop is only visible at `.full`, where leaving it up for the whole slide
            // would dim the map the sheet is uncovering.
            panel.backdropView.alpha = 0
        } completion: { _ in
            completion()
        }
    }

    /// Clears the presenter's state, untracks the scroll view, restores the tab bar unless the
    /// caller is about to present again, and runs the dismissal handler.
    /// Returns the panel that was showing, or `nil` if there wasn't one.
    @discardableResult
    private func releaseCurrentPresentation(restoringTabBar: Bool = true) -> FloatingPanelController? {
        guard let panel else { return nil }

        let handler = dismissHandler
        self.panel = nil
        self.navigation = nil
        self.dismissHandler = nil

        if let trackingScrollView = panel.trackingScrollView {
            panel.untrack(scrollView: trackingScrollView)
        }

        if restoringTabBar {
            setHostTabBarHidden(false, animated: true)
            hostTabBarController = nil
        }

        handler?()

        return panel
    }

    // MARK: - Tab Bar

    /// Hides the host tab bar for the life of the sheet, and puts it back afterwards.
    ///
    /// The panel is parented to the map view controller, which lives inside the tab bar
    /// controller's content area — so the tab bar draws over the sheet, and no z-order work
    /// inside the map can change that (FloatingPanel also asserts against parenting a panel
    /// directly to a `UITabBarController`). Hiding it hands the sheet the whole bottom edge of
    /// the screen, the way Maps gives its place card that space, and leaves room for the sheet's
    /// own bottom chrome.
    ///
    /// A useful side effect: with the bar hidden the rider can't switch tabs out from under a
    /// live sheet, so there is no path that strands a hidden bar on another tab.
    private func setHostTabBarHidden(_ hidden: Bool, animated: Bool) {
        guard let hostTabBarController, hostTabBarController.isTabBarHidden != hidden else { return }
        hostTabBarController.setTabBarHidden(hidden, animated: animated)
    }

    /// Puts the tab bar back after an animated dismissal has finished.
    ///
    /// The bar's return grows the map's bottom safe area, and the sheet's `.half` anchor is a
    /// *fraction of the safe area* — so restoring it while the sheet is still onscreen re-solves
    /// the anchor and yanks the sheet up the screen before it can slide down. `.full` and `.tip`
    /// are absolute insets and barely move, which is why the jump only ever showed up at `.half`.
    /// Waiting until the sheet has left means nothing is onscreen to re-lay out.
    ///
    /// Skipped when another sheet arrived during the slide: that presentation wants the bar
    /// hidden, and it owns `hostTabBarController` now.
    private func restoreDeferredTabBar() {
        guard panel == nil else { return }

        setHostTabBarHidden(false, animated: true)
        hostTabBarController = nil
    }

    /// Keeps the bar transparent in every state so the header card's map snapshot runs
    /// edge-to-edge behind the chrome.
    ///
    /// A bar normally swaps its transparent `scrollEdgeAppearance` for the opaque
    /// `standardAppearance` once content scrolls under it. That swap is driven by the scroll
    /// view's adjusted content inset, and FloatingPanel forces
    /// `contentInsetAdjustmentBehavior = .never` on whatever it tracks — so the bar never
    /// learns it has been scrolled. Rather than fight for a transition that can't fire, the
    /// bar stays transparent and `trackScrollView(in:)` pins a hard scroll edge effect on the
    /// list instead, which is what actually keeps departures from sliding under the buttons.
    private func configureNavigationBar(_ navigationBar: UINavigationBar) {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
    }

    // MARK: - Scroll Tracking

    /// Hands the visible controller's scroll view to the panel so flicking the departures list
    /// resizes the sheet.
    ///
    /// `StopPageViewController` is a `UIHostingController` around a SwiftUI `List`, which offers
    /// no public handle on its backing collection view, so the scroll view is found by walking
    /// the hierarchy. When the walk comes up empty — which a future SwiftUI layout change could
    /// cause — the sheet stays fully usable with grabber-only dragging.
    private func trackScrollView(in viewController: UIViewController, allowingRetry: Bool = true) {
        guard let panel else { return }

        if let trackingScrollView = panel.trackingScrollView {
            panel.untrack(scrollView: trackingScrollView)
        }

        viewController.view.layoutIfNeeded()

        guard let scrollView = viewController.view.nearestDescendantScrollView() else {
            // SwiftUI can defer building the list's scroll view past the first layout pass, so
            // give it one more runloop turn before settling for grabber-only dragging.
            guard allowingRetry else { return }
            DispatchQueue.main.async { [weak self, weak viewController] in
                guard let self, let viewController,
                      viewController === self.navigation?.topViewController else { return }
                self.trackScrollView(in: viewController, allowingRetry: false)
            }
            return
        }

        // No top edge effect at all. It exists to keep content from smearing under floating bar
        // chrome, and the sheet has none — `StopPageViewController` moves its controls to a
        // bottom toolbar when presented this way, leaving the sheet's top edge as a bare grabber
        // over the page's own opaque header. Left on, the effect blurs that header's stop name.
        if #available(iOS 26.0, *) {
            scrollView.topEdgeEffect.isHidden = true
        }

        panel.track(scrollView: scrollView)
    }
}

// MARK: - UINavigationControllerDelegate

extension StopSheetPresenter: UINavigationControllerDelegate {
    /// The stop page at the sheet's root shows no navigation bar; everything pushed on top of it
    /// gets one back for its title and back button.
    ///
    /// Beyond having nothing to put in it — the page's chrome is its bottom toolbar and its own
    /// header's close button — a visible bar costs the page a bar's worth of top safe area. The
    /// header is a `safeAreaInset(edge: .top)`, so it *inherits* that inset and lays its content
    /// out below it while its background still fills the whole strip, leaving ~50 pt of dead
    /// space above the stop name that no amount of SwiftUI sizing can reclaim.
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        navigationController.setNavigationBarHidden(hidesNavigationBar(for: viewController), animated: animated)
    }

    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        trackScrollView(in: viewController)
    }

    /// Only the sheet-configured stop page hides the bar. Anything else in this stack — including
    /// a stop page pushed from a nearby-stops list, which keeps its navigation-bar chrome — needs it.
    private func hidesNavigationBar(for viewController: UIViewController) -> Bool {
        (viewController as? StopPageViewController)?.showsBottomToolbar ?? false
    }
}

// MARK: - Layout

/// `FloatingPanelBottomLayout` with a `.tip` detent tall enough to hold the collapsed stop
/// header.
///
/// The stock anchor is a flat 69 pt, which fits the collapsed header at the default content size
/// category and nothing above it. Overflow there is not a graceful crop — see
/// `StopSheetHeaderMetrics` — so the anchor grows with the type size instead. `.full` and `.half`
/// are the stock anchors; only the peek detent has content it must be measured against.
nonisolated final class StopSheetLayout: FloatingPanelBottomLayout {
    private let tipInset: CGFloat

    init(traitCollection: UITraitCollection) {
        let stockTipInset: CGFloat = 69.0
        // The grabber strip sits inside the surface but above the content view, so the header's
        // share of a detent is the anchor minus that clearance — hence adding it back here.
        let needed = StopSheetHeaderMetrics.collapsedHeight(for: traitCollection) + StopSheetPresenter.grabberClearance
        tipInset = max(stockTipInset, needed)
        super.init()
    }

    override var anchors: [FloatingPanelState: FloatingPanelLayoutAnchoring] {
        var anchors = super.anchors
        anchors[.tip] = FloatingPanelLayoutAnchor(absoluteInset: tipInset, edge: .bottom, referenceGuide: .safeArea)
        return anchors
    }
}

// MARK: - FloatingPanelControllerDelegate

extension StopSheetPresenter: FloatingPanelControllerDelegate {

    /// Re-measures the `.tip` detent when the rider changes their text size while a sheet is up.
    func floatingPanel(_ fpc: FloatingPanelController, layoutFor newCollection: UITraitCollection) -> FloatingPanelLayout {
        StopSheetLayout(traitCollection: newCollection)
    }

    /// Fires when the rider swipes the sheet away. FloatingPanel has already detached the panel
    /// and removed it from the parent by this point, so this only has to release the
    /// presenter's own state, restore the tab bar, and run the dismissal handler.
    func floatingPanelDidRemove(_ fpc: FloatingPanelController) {
        guard fpc === panel else { return }
        releaseCurrentPresentation()
    }

    /// Fires on every detent transition. Notifies the stop page so it can hide its bottom
    /// toolbar when the sheet is at `.tip` (nearly offscreen).
    func floatingPanelDidChangeState(_ fpc: FloatingPanelController) {
        guard fpc === panel,
              let stopVC = navigation?.topViewController as? StopPageViewController else { return }
        stopVC.setAtTip(fpc.state == .tip)
    }
}
