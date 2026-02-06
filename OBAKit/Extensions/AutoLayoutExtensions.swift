//
//  AutoLayoutExtensions.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore

// MARK: - Autolayoutable

extension UIView {
    public enum AutoLayoutPinTarget: Int {
        case edges, layoutMargins, readableContent, safeArea
    }
}


// MARK: - Extension UIView

extension UIView {

    /// Returns a view suitable for use as a spacer.
    ///
    /// - Parameter height: The height of the spacer.
    /// - Returns: The spacer view.
    public class func spacerView(height: CGFloat) -> UIView {
        let spacer = UIView.autolayoutNew()
        NSLayoutConstraint.activate([
            spacer.heightAnchor.constraint(equalToConstant: height)
        ])
        return spacer
    }

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
            pinToSuperview(AutoLayoutPinTarget.edges)
        }

        return wrapper
    }

    public struct LayoutConstraints {
        public let top: NSLayoutConstraint
        public let bottom: NSLayoutConstraint
        public let leading: NSLayoutConstraint
        public let trailing: NSLayoutConstraint
    }

    private func pinToSuperview(_ pinTargets: DirectionalPinTargets, insets: NSDirectionalEdgeInsets = .zero, editConstraints: ((LayoutConstraints) -> Void)? = nil) {
        guard let superview = superview else {
            return
        }

        translatesAutoresizingMaskIntoConstraints = false

        let leadingAnchorable = anchorable(for: superview, pinTarget: pinTargets.leading)
        let trailingAnchorable = anchorable(for: superview, pinTarget: pinTargets.trailing)
        let topAnchorable = anchorable(for: superview, pinTarget: pinTargets.top)
        let bottomAnchorable = anchorable(for: superview, pinTarget: pinTargets.bottom)

        let leading = leadingAnchor.constraint(equalTo: leadingAnchorable.leadingAnchor, constant: insets.leading)
        let trailing = trailingAnchor.constraint(equalTo: trailingAnchorable.trailingAnchor, constant: insets.trailing)
        let top = topAnchor.constraint(equalTo: topAnchorable.topAnchor, constant: insets.top)
        let bottom = bottomAnchor.constraint(equalTo: bottomAnchorable.bottomAnchor, constant: insets.bottom)

        let constraints = LayoutConstraints(top: top, bottom: bottom, leading: leading, trailing: trailing)
        editConstraints?(constraints)

        NSLayoutConstraint.activate([leading, trailing, top, bottom])
    }

    private func anchorable(for view: UIView, pinTarget: UIView.AutoLayoutPinTarget) -> Anchorable {
        switch pinTarget {
        case .edges: return view
        case .layoutMargins: return view.layoutMarginsGuide
        case .readableContent: return view.readableContentGuide
        case .safeArea: return view.safeAreaLayoutGuide
        }
    }

    /// Pins the receiver to the specified part of its superview, and sets `self.translatesAutoresizingMaskIntoConstraints` to `false` as a convenience.
    ///
    /// Does nothing if the receiver does not have a superview.
    ///
    /// - Parameters:
    ///   - pinTarget: Which part of the superview to pin to: edges, layout margins, or safe area.
    ///   - insets: Optional inset from the pinTarget. Defaults to zero.
    ///   - editConstraints: Allows you to modify the four constraints before they are activated. The order is: top, bottom, leading, trailing.
    public func pinToSuperview(_ pinTarget: UIView.AutoLayoutPinTarget, insets: NSDirectionalEdgeInsets = .zero, editConstraints: ((LayoutConstraints) -> Void)? = nil) {
        pinToSuperview(DirectionalPinTargets(pinTarget: pinTarget), insets: insets, editConstraints: editConstraints)
    }
}

// MARK: - Extension NSLayoutConstraint

public extension NSLayoutConstraint {
    /// Chainable method for setting the constraint's priority.
    /// - Parameter priority: The layout priority for this constraint.
    /// - Returns: `self`
    func setPriority(_ priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}

// MARK: - DirectionalPinTargets/Anchorable

public struct DirectionalPinTargets {
    public let leading: UIView.AutoLayoutPinTarget
    public let trailing: UIView.AutoLayoutPinTarget
    public let top: UIView.AutoLayoutPinTarget
    public let bottom: UIView.AutoLayoutPinTarget

    public init(pinTarget: UIView.AutoLayoutPinTarget) {
        leading = pinTarget
        trailing = pinTarget
        top = pinTarget
        bottom = pinTarget
    }

    public init(leading: UIView.AutoLayoutPinTarget, trailing: UIView.AutoLayoutPinTarget, top: UIView.AutoLayoutPinTarget, bottom: UIView.AutoLayoutPinTarget) {
        self.leading = leading
        self.trailing = trailing
        self.top = top
        self.bottom = bottom
    }

    public init(leadingTrailing: UIView.AutoLayoutPinTarget, topBottom: UIView.AutoLayoutPinTarget) {
        self.leading = leadingTrailing
        self.trailing = leadingTrailing
        self.top = topBottom
        self.bottom = topBottom
    }

    public static var edges: DirectionalPinTargets { .init(pinTarget: .edges) }
    public static var layoutMargins: DirectionalPinTargets { .init(pinTarget: .layoutMargins) }
    public static var readableContent: DirectionalPinTargets { .init(pinTarget: .readableContent) }
    public static var safeArea: DirectionalPinTargets { .init(pinTarget: .safeArea) }
}

public protocol Anchorable {
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
