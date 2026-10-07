/**
 *  BulletinBoard
 *  Copyright (c) 2017 - present Alexis Aubry. Licensed under the MIT license.
 */

import UIKit

/**
 * An object that manages the presentation of a bulletin.
 *
 * You create a bulletin manager using the `init(rootItem:)` initializer, where `rootItem` is the
 * first bulletin item to display. An item represents the contents displayed on a single card.
 *
 * The manager works like a navigation controller. You can push new items to the stack to display them,
 * and pop existing ones to go back.
 *
 * You must call the `prepare` method before displaying the view controller.
 *
 * `BLTNItemManager` must only be used from the main thread.
 */

@objc final class BLTNItemManager: NSObject {

    /// Bulletin view controller.
    fileprivate var bulletinController: BulletinViewController!

    // MARK: - Background

    /**
     * The background color of the bulletin card. Defaults to `systemBackground`.
     *
     * Set this value before presenting the bulletin. Changing it after will have no effect.
     */

    @objc var backgroundColor: UIColor = .systemBackground

    /**
     * The style of the view covering the content. Defaults to `.dimmed`.
     *
     * Set this value before presenting the bulletin. Changing it after will have no effect.
     */

    @objc var backgroundViewStyle: BLTNBackgroundViewStyle = .dimmed

    // MARK: - Status Bar

    /**
     * The style of status bar to use with the bulltin. Defaults to `.automatic`.
     *
     * Set this value before presenting the bulletin. Changing it after will have no effect.
     */

    @objc var statusBarAppearance: BLTNStatusBarAppearance = .automatic

    /**
     * The style of status bar animation. Defaults to `.fade`.
     *
     * Set this value before presenting the bulletin. Changing it after will have no effect.
     */

    @objc var statusBarAnimation: UIStatusBarAnimation = .fade

    /**
     * The home indicator for iPhone X should be hidden or not. Defaults to false.
     *
     * Set this value before presenting the bulletin. Changing it after will have no effect.
     */

    @objc var hidesHomeIndicator: Bool = false

    // MARK: - Card Presentation

    /**
     * The spacing between the edge of the screen and the edge of the card. Defaults to regular.
     *
     * Set this value before presenting the bulletin. Changing it after will have no effect.
     */

    @objc var edgeSpacing: BLTNSpacing = .regular

    /**
     * The rounded corner radius of the bulletin card. Defaults to 12, and 36 on iPhone X.
     *
     * Set this value before calling `prepare`. Changing it after will have no effect.
     */

    @objc var cardCornerRadius: NSNumber?

    /**
     * Whether swipe to dismiss should be allowed. Defaults to true.
     *
     * If you set this value to true, the user will be able to drag the card, and swipe down to
     * dismiss it (if allowed by the current item).
     *
     * If you set this value to false, no pan gesture will be recognized, and swipe to dismiss
     * won't be available.
     */

    @objc var allowsSwipeInteraction: Bool = true

    /**
     * Tells us if a bulletin is currently being shown. Defaults to false
     */

    @objc var isShowingBulletin: Bool {
        return bulletinController?.presentingViewController != nil
    }

    // MARK: - Private Properties

    var currentItem: BLTNItem

    fileprivate let rootItem: BLTNItem
    fileprivate var itemsStack: [BLTNItem]
    fileprivate var previousItem: BLTNItem?

    fileprivate var isPrepared: Bool = false
    fileprivate var isPreparing: Bool = false
    fileprivate var shouldDisplayActivityIndicator: Bool = false
    fileprivate var lastActivityIndicatorColor: UIColor = .label

    // MARK: - Initialization

    /**
     * Creates a bulletin manager and sets the first item to display.s
     *
     * - parameter rootItem: The first item to display.
     */

    @objc init(rootItem: BLTNItem) {

        self.rootItem = rootItem
        self.itemsStack = []
        self.currentItem = rootItem

    }

    isolated deinit {

        tearDownItemsChain(startingAt: self.rootItem)

        for item in itemsStack {
            tearDownItemsChain(startingAt: item)
        }

    }

    @available(*, unavailable, message: "Use init(rootItem:) instead.")
    override init() {
        fatalError("BLTNItemManager.init is unavailable. Use init(rootItem:) instead.")
    }

}

// MARK: - Interacting with the Bulletin

extension BLTNItemManager {

    /**
     * Prepares the bulletin interface and displays the root item.
     *
     * This method must be called before any other interaction with the bulletin.
     */

    fileprivate func prepare() {

        assertIsMainThread()

        bulletinController = BulletinViewController()
        bulletinController.manager = self

        bulletinController.modalPresentationStyle = .overFullScreen
        bulletinController.transitioningDelegate = bulletinController
        bulletinController.loadBackgroundView()
        bulletinController.setNeedsStatusBarAppearanceUpdate()
        bulletinController.setNeedsUpdateOfHomeIndicatorAutoHidden()

        isPrepared = true
        isPreparing = true
        shouldDisplayActivityIndicator = rootItem.shouldStartWithActivityIndicator

        refreshCurrentItemInterface()
        isPreparing = false

    }

    /**
     * Presents a view controller above the bulletin card.
     *
     * This is useful if you want to present an alert or a Safari view contoller in response to user
     * action.
     *
     * - parameter viewController: The view controller to present.
     * - parameter animated: Whether presentation should be animated.
     * - parameter completion: An optional completion block to run after presentation
     * has completed. Defaults to `nil`.
     */

    @objc(presentViewControllerAboveBulletin:animated:completion:)
    func present(_ viewController: UIViewController, animated: Bool, completion: (() -> Void)? = nil) {
        assertIsPrepared()
        self.bulletinController.present(viewController, animated: animated, completion: completion)
    }

    /**
     * Hides the contents of the stack and displays an activity indicator view.
     *
     * Use this method if you need to perform a long task or fetch some data before changing the item.
     *
     * Displaying the loading indicator does not change the height of the page or the current item. It will disable
     * dismissal by tapping and swiping to allow the task to complete and avoid resource deallocation.
     *
     * - parameter color: The color of the activity indicator to display. Defaults to .label.
     *
     * Displaying the loading indicator does not change the height of the page or the current item.
     */

    @objc func displayActivityIndicator(color: UIColor? = nil) {

        assertIsPrepared()
        assertIsMainThread()

        shouldDisplayActivityIndicator = true
        lastActivityIndicatorColor = color ?? defaultActivityIndicatorColor

        bulletinController.displayActivityIndicator(color: lastActivityIndicatorColor)
    }

    /// Provides a default color for activity indicator views.
    /// Defaults to .label.
    private var defaultActivityIndicatorColor: UIColor {
        return .label
    }

    /**
     * Hides the activity indicator and displays the current item.
     *
     * You can also call one of `popItem`, `popToRootItem` and `pushItem` if you need to hide the activity
     * indicator and change the current item.
     */

    @objc func hideActivityIndicator() {

        assertIsPrepared()
        assertIsMainThread()

        shouldDisplayActivityIndicator = false
        bulletinController.swipeInteractionController?.cancelIfNeeded()
        refreshCurrentItemInterface(elementsChanged: false)

    }

    /**
     * Displays a new item after the current one.
     * - parameter item: The item to display.
     */

    @objc(pushItem:)
    func push(item: BLTNItem) {

        assertIsPrepared()
        assertIsMainThread()

        previousItem = currentItem
        itemsStack.append(item)

        currentItem = item

        shouldDisplayActivityIndicator = item.shouldStartWithActivityIndicator
        refreshCurrentItemInterface()

    }

    /**
     * Removes the current item from the stack and displays the previous item.
     */

    @objc func popItem() {

        assertIsPrepared()
        assertIsMainThread()

        guard let previousItem = itemsStack.popLast() else {
            popToRootItem()
            return
        }

        self.previousItem = previousItem

        guard let currentItem = itemsStack.last else {
            popToRootItem()
            return
        }

        self.currentItem = currentItem

        shouldDisplayActivityIndicator = currentItem.shouldStartWithActivityIndicator
        refreshCurrentItemInterface()

    }

    /**
     * Removes items from the stack until a specific item is found.
     * - parameter item: The item to seek.
     * - parameter orDismiss: If true, dismiss bullein if not found. Otherwise popToRootItem()
     */

    @objc(popToItem:orDismiss:)
    func popTo(item: BLTNItem, orDismiss: Bool) {

        assertIsPrepared()
        assertIsMainThread()

        if let index = itemsStack.firstIndex(where: { $0 === item }) {

            self.currentItem = itemsStack[index]
            shouldDisplayActivityIndicator = currentItem.shouldStartWithActivityIndicator
            refreshCurrentItemInterface()

            for removeIndex in (index+1..<itemsStack.count).reversed() {
                let removeItem = itemsStack.remove(at: removeIndex)
                tearDownItemsChain(startingAt: removeItem)
            }
            return
        }

        if item !== rootItem, orDismiss {
            dismissBulletin(animated: true)
        } else {
            popToRootItem()
        }
    }

    /**
     * Removes all the items from the stack and displays the root item.
     */

    @objc func popToRootItem() {

        assertIsPrepared()
        assertIsMainThread()

        guard currentItem !== rootItem else {
            return
        }

        previousItem = currentItem
        currentItem = rootItem

        itemsStack = []

        shouldDisplayActivityIndicator = rootItem.shouldStartWithActivityIndicator
        refreshCurrentItemInterface()

    }

    /**
     * Displays the next item, if the `next` property of the current item is set.
     *
     * - warning: If you call this method but `next` is `nil`, an exception will be raised.
     */

    @objc func displayNextItem() {

        guard let next = currentItem.next else {
            preconditionFailure("Calling BLTNItemManager.displayNextItem, but the current item has no nextItem.")
        }

        push(item: next)

    }

}

// MARK: - Presentation / Dismissal

extension BLTNItemManager {

    /**
     * Presents the bulletin above the specified view controller.
     *
     * - parameter presentingVC: The view controller to use to present the bulletin.
     * - parameter animated: Whether to animate presentation. Defaults to `true`.
     * - parameter completion: An optional block to execute after presentation. Default to `nil`.
     */

    @objc(showBulletinAboveViewController:animated:completion:)
    func showBulletin(above presentingVC: UIViewController,
                      animated: Bool = true,
                      completion: (() -> Void)? = nil) {

        self.prepare()

        let isDetached = bulletinController.presentingViewController == nil
        assert(isDetached, "Attempt to present a Bulletin that is already presented.")

        assertIsPrepared()
        assertIsMainThread()
        bulletinController.loadView()

        let refreshActivityIndicator = shouldDisplayActivityIndicator && isDetached

        if refreshActivityIndicator {
            bulletinController.displayActivityIndicator(color: lastActivityIndicatorColor)
        }

        bulletinController.modalPresentationCapturesStatusBarAppearance = true
        presentingVC.present(bulletinController, animated: animated, completion: completion)

    }

    /**
     * Dismisses the bulletin and clears the current page. You will have to call `prepare` before
     * presenting the bulletin again.
     *
     * This method will call the `dismissalHandler` block of the current item if it was set.
     *
     * - parameter animated: Whether to animate dismissal. Defaults to `true`.
     */

    @objc(dismissBulletinAnimated:)
    func dismissBulletin(animated: Bool = true) {

        assertIsPrepared()
        assertIsMainThread()

        currentItem.tearDown()
        currentItem.manager = nil

        bulletinController.dismiss(animated: animated) {
            self.completeDismissal()
        }

        isPrepared = false

    }

    /**
     * Finishes a dismissal the user drove by swiping the card away.
     *
     * OBA: performs the item teardown and `isPrepared` reset that
     * `dismissBulletin(animated:)` does before handing off to `completeDismissal()`.
     */

    @nonobjc func completeInteractiveDismissal() {

        currentItem.tearDown()
        currentItem.manager = nil
        isPrepared = false

        completeDismissal()

    }

    /**
     * Tears down the view controller and item stack after dismissal is finished.
     */

    @nonobjc func completeDismissal() {

        currentItem.onDismiss()

        for arrangedSubview in bulletinController.contentStackView.arrangedSubviews {
            bulletinController.contentStackView.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }

        bulletinController.backgroundView = nil
        bulletinController.manager = nil
        bulletinController.transitioningDelegate = nil

        bulletinController = nil

        currentItem = self.rootItem
        itemsStack.removeAll()

    }

}

// MARK: - Transitions

extension BLTNItemManager {

    var needsCloseButton: Bool {
        return currentItem.isDismissable && currentItem.requiresCloseButton
    }

    /// Refreshes the interface for the current item.
    ///
    /// When `elementsChanged` is `false` only the activity indicator state
    /// changes, so the current item's views stay as they are. (OBA: upstream
    /// rebuilt them anyway, which re-pointed the item's `actionButton` at an
    /// off-screen button and could pull a reused view out of the card.)
    fileprivate func refreshCurrentItemInterface(elementsChanged: Bool = true) {

        bulletinController.isDismissable = false
        bulletinController.swipeInteractionController?.cancelIfNeeded()
        bulletinController.refreshSwipeInteractionController()

        let oldArrangedSubviews = bulletinController.contentStackView.arrangedSubviews

        guard elementsChanged else {
            bulletinController.hideActivityIndicator()
            let transitionAnimationChain = AnimationChain(duration: transitionDuration)
            transitionAnimationChain.add(makeFinalAnimationPhase(currentElements: oldArrangedSubviews,
                                                                 oldArrangedSubviews: [],
                                                                 elementsChanged: false))
            transitionAnimationChain.start()
            return
        }

        // Tear down old item

        previousItem?.tearDown()
        previousItem?.manager = nil
        previousItem = nil

        // Create new views

        let newArrangedSubviews = currentItem.makeArrangedSubviews()
        let oldHideableArrangedSubviews = recursiveArrangedSubviews(in: oldArrangedSubviews)
        let newHideableArrangedSubviews = recursiveArrangedSubviews(in: newArrangedSubviews)

        currentItem.setUp()
        currentItem.manager = self

        for arrangedSubview in newHideableArrangedSubviews {
            arrangedSubview.isHidden = !isPreparing
        }

        for arrangedSubview in newArrangedSubviews {
            bulletinController.contentStackView.addArrangedSubview(arrangedSubview)
        }

        // Animate transition

        let showActivityIndicator = shouldDisplayActivityIndicator

        let hideSubviewsAnimationPhase = AnimationPhase(relativeDuration: 1/3, curve: .linear)

        hideSubviewsAnimationPhase.block = {

            if !showActivityIndicator {
                self.bulletinController.hideActivityIndicator()
            }

            for arrangedSubview in oldArrangedSubviews + newArrangedSubviews {
                arrangedSubview.alpha = 0
            }

        }

        let transitionAnimationChain = AnimationChain(duration: transitionDuration)
        transitionAnimationChain.add(hideSubviewsAnimationPhase)
        transitionAnimationChain.add(makeDisplayNewItemsAnimationPhase(hiding: oldHideableArrangedSubviews,
                                                                       showing: newHideableArrangedSubviews))
        transitionAnimationChain.add(makeFinalAnimationPhase(currentElements: newArrangedSubviews,
                                                             oldArrangedSubviews: oldArrangedSubviews,
                                                             elementsChanged: true))
        transitionAnimationChain.start()

    }

    /// Creates the middle phase of an item change: swaps which arranged
    /// subviews are hidden, then tells the current item it will display.
    private func makeDisplayNewItemsAnimationPhase(hiding oldViews: [UIView],
                                                   showing newViews: [UIView]) -> AnimationPhase {

        let displayNewItemsAnimationPhase = AnimationPhase(relativeDuration: 1/3, curve: .linear)

        displayNewItemsAnimationPhase.block = {

            for arrangedSubview in oldViews {
                arrangedSubview.isHidden = true
            }

            for arrangedSubview in newViews {
                arrangedSubview.isHidden = false
            }

        }

        displayNewItemsAnimationPhase.completionHandler = {
            self.currentItem.willDisplay()
        }

        return displayNewItemsAnimationPhase

    }

    /// The duration of a full item transition; zero while preparing.
    private var transitionDuration: TimeInterval {
        isPreparing ? 0 : 0.75
    }

    /// Creates the last phase of a refresh: fades in `currentElements` and
    /// finishes the transition.
    private func makeFinalAnimationPhase(currentElements: [UIView],
                                         oldArrangedSubviews: [UIView],
                                         elementsChanged: Bool) -> AnimationPhase {

        let showActivityIndicator = shouldDisplayActivityIndicator
        let contentAlpha: CGFloat = showActivityIndicator ? 0 : 1

        let finalAnimationPhase = AnimationPhase(relativeDuration: 1/3, curve: .linear)

        finalAnimationPhase.block = {

            self.bulletinController.contentStackView.alpha = contentAlpha
            self.bulletinController.updateCloseButton(isRequired: self.needsCloseButton && !showActivityIndicator)

            for arrangedSubview in currentElements {
                arrangedSubview.alpha = contentAlpha
            }

        }

        finalAnimationPhase.completionHandler = {

            self.bulletinController.isDismissable = self.currentItem.isDismissable && !showActivityIndicator

            if elementsChanged {

                self.currentItem.onDisplay()

                for arrangedSubview in oldArrangedSubviews {
                    self.bulletinController.contentStackView.removeArrangedSubview(arrangedSubview)
                    arrangedSubview.removeFromSuperview()
                }

            }

            UIAccessibility.post(notification: .screenChanged, argument: currentElements.first)

        }

        return finalAnimationPhase

    }

    /// Tears down every item on the stack starting from the specified item.
    fileprivate func tearDownItemsChain(startingAt item: BLTNItem) {

        item.tearDown()
        item.manager = nil

        if let next = item.next {
            tearDownItemsChain(startingAt: next)
            item.next = nil
        }

    }

    /// Returns all the arranged subviews.
    private func recursiveArrangedSubviews(in views: [UIView]) -> [UIView] {

        var arrangedSubviews: [UIView] = []

        for view in views {

            if let stack = view as? UIStackView {
                arrangedSubviews.append(stack)
                let recursiveViews = self.recursiveArrangedSubviews(in: stack.arrangedSubviews)
                arrangedSubviews.append(contentsOf: recursiveViews)
            } else {
                arrangedSubviews.append(view)
            }

        }

        return arrangedSubviews

    }

}

// MARK: - Utilities

extension BLTNItemManager {

    fileprivate func assertIsMainThread() {
        precondition(Thread.isMainThread, "BLTNItemManager must only be used from the main thread.")
    }

    fileprivate func assertIsPrepared() {
        precondition(isPrepared, "You must call the `prepare` function before interacting with the bulletin.")
    }

}
