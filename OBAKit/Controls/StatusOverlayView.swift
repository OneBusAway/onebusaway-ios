//
//  StatusOverlayView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 12/8/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import UIKit

/// An overlay view placed on top of a map to offer status text to the user, like
/// if they need to zoom in to see stops on the map, or if their search query returned no results.
public class StatusOverlayView: UIView {

    private var _innerPadding: CGFloat = 0 {
        didSet {
            statusOverlay.layer.cornerRadius = _innerPadding
            statusOverlay.contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: _innerPadding / 2.0, leading: _innerPadding, bottom: _innerPadding / 2.0, trailing: _innerPadding)
        }
    }
    @objc dynamic var innerPadding: CGFloat {
        get { return _innerPadding }
        set { _innerPadding = newValue }
    }

    private var _textColor: UIColor = .white {
        didSet {
            statusLabel.textColor = _textColor
        }
    }
    @objc dynamic var textColor: UIColor {
        get { return _textColor }
        set { _textColor = newValue }
    }

    private var _font: UIFont = UIFont.boldSystemFont(ofSize: UIFont.labelFontSize) {
        didSet {
            statusLabel.font = _font
        }
    }
    @objc dynamic var font: UIFont {
        get { return _font }
        set { _font = newValue }
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(statusOverlay)
        statusOverlay.pinToSuperview(.edges)

        statusOverlay.contentView.addSubview(statusLabel)
        statusLabel.pinToSuperview(.layoutMargins)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private lazy var statusOverlay: UIVisualEffectView = {
        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        blurView.backgroundColor = UIColor.white.withAlphaComponent(0.60)
        blurView.clipsToBounds = true
        return blurView
    }()

    /// Sets the text that is displayed on the status overlay
    public var text: String? {
        get {
            return statusLabel.text
        }
        set {
            statusLabel.text = newValue
        }
    }

    private lazy var statusLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.textColor = _textColor
        label.textAlignment = .center
        label.font = _font
        return label
    }()

    // MARK: - Animations

    private var showAnimator: UIViewPropertyAnimator?
    private var hideAnimator: UIViewPropertyAnimator?

    /// Displays the overlay, by default animating in the display of it.
    ///
    /// - Note: This method and `hideOverlay()` share a lock that prevents simultaneous access while an animation is occurring.
    ///
    /// - Parameters:
    ///   - message: The text to display on the overlay
    ///   - animated: Whether or not the display of the overlay should be animated.
    public func showOverlay(message: String, animated: Bool = true) {
        text = message

        // short-circuit the evaluation of this method and show the overlay if `animated` is false.
        guard animated else {
            statusOverlay.isHidden = false
            statusOverlay.alpha = 1.0
            return
        }

        // Bail out if we already have a 'show' animation running.
        guard showAnimator == nil else {
            return
        }

        hideAnimator?.stopAnimation(true)
        hideAnimator = nil

        statusOverlay.alpha = 0.0
        statusOverlay.isHidden = false

        let animator = UIViewPropertyAnimator(duration: UIView.inheritedAnimationDuration, curve: .easeInOut) { [weak self] in
            self?.statusOverlay.alpha = 1.0
        }
        animator.startAnimation()
        showAnimator = animator
    }

    /// Hides the overlay, by default animating it out.
    ///
    /// - Note: This method and `showOverlay(message:)` share a lock that prevents simultaneous access while an animation is occurring.
    ///
    /// - Parameter animated: Whether or not the display of the overlay should be animated.
    public func hideOverlay(animated: Bool = true) {
        // short-circuit the evaluation of this method and hide the overlay if `animated` is false.
        guard animated else {
            statusOverlay.isHidden = true
            statusOverlay.alpha = 0.0
            return
        }

        // Bail out if we already have a 'hide' animation running.
        guard hideAnimator == nil else {
            return
        }

        showAnimator?.stopAnimation(true)
        showAnimator = nil

        let animator = UIViewPropertyAnimator(duration: UIView.inheritedAnimationDuration, curve: .easeInOut) { [weak self] in
            self?.statusOverlay.alpha = 0.0
        }
        animator.addCompletion { [weak self] _ in
            self?.statusOverlay.isHidden = true
        }
        animator.startAnimation()
        hideAnimator = animator
    }
}
