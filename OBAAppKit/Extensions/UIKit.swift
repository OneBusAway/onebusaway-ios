//
//  UIKit.swift
//  OBAAppKit
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
    class func oba_horizontalStack(arrangedSubviews views: [UIView]) -> UIStackView {
        return oba_stack(axis: .horizontal, arrangedSubviews: views)
    }

    /// Creates a vertical axis stack view
    ///
    /// - Parameter views: The arranged subviews
    /// - Returns: The vertical stack view.
    class func oba_verticalStack(arangedSubviews views: [UIView]) -> UIStackView {
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
protocol Autolayoutable {
    static func autolayoutNew() -> Self
}

extension UIView: Autolayoutable {

    /// Creates a new instance of the receiver class, configured for use with Auto Layout.
    ///
    /// - Returns: An instance of the receiver class.
    static func autolayoutNew() -> Self {
        let view = self.init(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }
}

extension UIView {
    /// Embeds the receiver in a `UIView` suitable for placing inside of a
    /// stack view or another container view.
    ///
    /// - Parameter setConstraints: By default, the receiver is pinned to the edges of the container view. Set this to `false` to set up constraints yourself.
    /// - Returns: The wrapper view into which the receiver has been embedded.
    func embedInWrapperView(setConstraints: Bool = true) -> UIView {
        let wrapper = UIView(frame: .zero)
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(self)

        if setConstraints {
            pinEdgesToSuperview()
        }

        return wrapper
    }

    /// Pins the receiver to the safe area layout anchors of its superview. Does nothing if the receiver is not a subview.
    func pinEdgesToSuperviewSafeArea() {
        guard let superview = superview else {
            return
        }

        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: superview.safeAreaLayoutGuide.leadingAnchor),
            trailingAnchor.constraint(equalTo: superview.safeAreaLayoutGuide.trailingAnchor),
            topAnchor.constraint(equalTo: superview.safeAreaLayoutGuide.topAnchor),
            bottomAnchor.constraint(equalTo: superview.safeAreaLayoutGuide.bottomAnchor),
        ])
    }

    /// Pins the receiver to the layout anchors of its superview. Does nothing if the receiver is not a subview.
    func pinEdgesToSuperview() {
        guard let superview = superview else {
            return
        }

        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: superview.leadingAnchor),
            trailingAnchor.constraint(equalTo: superview.trailingAnchor),
            topAnchor.constraint(equalTo: superview.topAnchor),
            bottomAnchor.constraint(equalTo: superview.bottomAnchor),
        ])
    }
}
