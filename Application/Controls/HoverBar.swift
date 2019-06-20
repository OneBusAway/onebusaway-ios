//
//  HoverBar.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 2/9/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import UIKit

fileprivate let defaultOrientation = NSLayoutConstraint.Axis.horizontal

/// A UIView subclass similar to UIToolBar but designed to hover over other content.
///
/// - Note: This class is a Swift port of [ISHHoverBar](https://github.com/iosphere/ISHHoverBar/).
///
public class HoverBar: RoundedShadowView {

    // MARK: - Public Interface

    /// Array of UIBarButtonItem to be included in the bar. Currently only items with a title, image, or customView of type UIControl are supported.
    public var items = [UIBarButtonItem]() {
        didSet {
            reloadControls()
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }

    /// The orientation of the hover bar. Default is horizontal.
    public var orientation: NSLayoutConstraint.Axis = defaultOrientation {
        didSet {
            guard oldValue != orientation else { return }

            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }

    /// The visual effect used for the bar's background. Default is an extra light blur effect.
    public var effect: UIVisualEffect? {
        set {
            backgroundView.effect = newValue
        }
        get {
            return backgroundView.effect
        }
    }

    public func reload() {
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    // MARK: - Init

    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    private func commonInit() {
        fillColor = .clear

        addSubview(backgroundView)
        backgroundView.pinToSuperview(.edges)

        backgroundView.contentView.addSubview(stackView)
        stackView.pinToSuperview(.edges)
    }

    // MARK: - Private

    private let stackView: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [])
        stack.axis = defaultOrientation
        stack.spacing = 2
        stack.distribution = .fillEqually
        return stack
    }()

    private let backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .extraLight))
    private var itemControlsMap = NSMapTable<UIControl, UIBarButtonItem>.weakToWeakObjects()

    private func reloadControls() {
        resetControls()

        for barItem in items {
            guard let control = buildControlForBarButtonItem(barItem) else {
                continue
            }

            itemControlsMap.setObject(barItem, forKey: control)
            stackView.addArrangedSubview(control)
        }
    }

    private func buildControlForBarButtonItem(_ item: UIBarButtonItem) -> UIControl? {
        if let ctl = item.customView as? UIControl {
            return ctl
        }

        precondition(item.image != nil || item.title != nil)

        let button = StackedButton.autolayoutNew()
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.textLabel.text = item.title
        button.imageView.image = item.image
        button.accessibilityLabel = item.accessibilityLabel
        button.addTarget(self, action: #selector(handleButtonAction(_:)), for: .touchUpInside)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 40.0),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 40.0)
        ])
        return button
    }

    @objc private func handleButtonAction(_ sender: UIControl) {
        guard
            let barItem = itemControlsMap.object(forKey: sender),
            let target = barItem.target,
            let action = barItem.action
        else {
            return
        }

        _ = target.perform(action, with: barItem)
    }

    private func resetControls() {
        for control in stackView.arrangedSubviews {
            control.removeFromSuperview()
        }

        itemControlsMap.removeAllObjects()
    }
}
