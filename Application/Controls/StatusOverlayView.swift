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

    private let lock = NSLock()

    /// Animates in the display of the overlay
    ///
    /// - Note: This method and `hideOverlay()` share a lock that prevents simultaneous access while an animation is occurring.
    /// - Parameter message: The text to display on the overlay
    public func showOverlay(message: String) {
        text = message

        guard lock.try() else {
            return
        }

        statusOverlay.alpha = 0.0
        statusOverlay.isHidden = false

        UIView.animate(withDuration: UIView.inheritedAnimationDuration, animations: { [weak self] in
            self?.statusOverlay.alpha = 1.0
        }, completion: { [weak self] _ in
            self?.lock.unlock()
        })
    }

    /// Animates out the display of the overlay
    ///
    /// - Note: This method and `showOverlay(message:)` share a lock that prevents simultaneous access while an animation is occurring.
    public func hideOverlay() {
        guard lock.try() else {
            return
        }

        UIView.animate(withDuration: UIView.inheritedAnimationDuration, animations: { [weak self] in
            self?.statusOverlay.alpha = 0.0
        }, completion: { [weak self] _ in
            self?.statusOverlay.isHidden = true
            self?.lock.unlock()
        })
    }
}
