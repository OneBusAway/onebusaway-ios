//
//  UIKit.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/25/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import UIKit

// MARK: - UIStackView

extension UIStackView {
    /// Creates a horizontal axis stack view
    ///
    /// - Parameter views: The arranged subviews
    /// - Returns: The horizontal stack view.
    public class func oba_horizontalStack(arrangedSubviews views: [UIView]) -> UIStackView {
        return oba_stack(axis: .horizontal, arrangedSubviews: views)
    }

    /// Creates a vertical axis stack view
    ///
    /// - Parameter views: The arranged subviews
    /// - Returns: The vertical stack view.
    public class func oba_verticalStack(arangedSubviews views: [UIView]) -> UIStackView {
        return oba_stack(axis: .vertical, arrangedSubviews: views)
    }

    private class func oba_stack(axis: NSLayoutConstraint.Axis, arrangedSubviews views: [UIView]) -> UIStackView {
        let stack = UIStackView.init(arrangedSubviews: views)
        stack.axis = axis
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }
}

// MARK: - UIView

/// Protocol support for improving Auto Layout-compatible view creation.
public protocol Autolayoutable {
    static func autolayoutNew() -> Self
}

extension UIView: Autolayoutable {

    /// Creates a new instance of the receiver class, configured for use with Auto Layout.
    ///
    /// - Returns: An instance of the receiver class.
    public static func autolayoutNew() -> Self {
        let view = self.init(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }
}

public enum AutoLayoutPinTarget: Int {
    case safeArea, layoutMargins, edges
}

extension UIView {
    /// Embeds the receiver in a `UIView` suitable for placing inside of a
    /// stack view or another container view.
    ///
    /// - Parameter setConstraints: By default, the receiver is pinned to the edges of the container view. Set this to `false` to set up constraints yourself.
    /// - Returns: The wrapper view into which the receiver has been embedded.
    public func embedInWrapperView(setConstraints: Bool = true) -> UIView {
        let wrapper = UIView(frame: .zero)
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(self)

        if setConstraints {
            pinToSuperview(.edges)
        }

        return wrapper
    }

    /// Pins the receiver to the specified part of its superview, and sets `self.translatesAutoresizingMaskIntoConstraints` to `false` as a convenience.
    ///
    /// Does nothing if the receiver does not have a superview.
    public func pinToSuperview(_ pinTarget: AutoLayoutPinTarget, insets: NSDirectionalEdgeInsets = .zero) {
        guard let superview = superview else {
            return
        }

        translatesAutoresizingMaskIntoConstraints = false

        let anchorable: Anchorable
        switch pinTarget {
        case .edges:
            anchorable = superview
        case .layoutMargins:
            anchorable = superview.layoutMarginsGuide
        case .safeArea:
            anchorable = superview.safeAreaLayoutGuide
        }

        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: anchorable.leadingAnchor, constant: insets.leading),
            trailingAnchor.constraint(equalTo: anchorable.trailingAnchor, constant: insets.trailing),
            topAnchor.constraint(equalTo: anchorable.topAnchor, constant: insets.top),
            bottomAnchor.constraint(equalTo: anchorable.bottomAnchor, constant: insets.bottom),
        ])
    }
}

protocol Anchorable {
    var leadingAnchor: NSLayoutXAxisAnchor { get }
    var trailingAnchor: NSLayoutXAxisAnchor { get }
    var leftAnchor: NSLayoutXAxisAnchor { get }
    var rightAnchor: NSLayoutXAxisAnchor { get }
    var topAnchor: NSLayoutYAxisAnchor { get }
    var bottomAnchor: NSLayoutYAxisAnchor { get }
    var widthAnchor: NSLayoutDimension { get }
    var heightAnchor: NSLayoutDimension { get }
    var centerXAnchor: NSLayoutXAxisAnchor { get }
    var centerYAnchor: NSLayoutYAxisAnchor { get }
}

extension UIView: Anchorable {}
extension UILayoutGuide: Anchorable {}
