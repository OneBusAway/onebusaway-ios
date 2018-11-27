//
//  UIKit.swift
//  OBAAppKit
//
//  Created by Aaron Brethorst on 11/25/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import UIKit

// MARK: - NSLayoutAnchor

extension NSLayoutAnchor {
    @objc @discardableResult
    public func pin(to anchor: NSLayoutAnchor) -> NSLayoutConstraint {
        let c = constraint(equalTo: anchor)
        c.isActive = true

        return c
    }
}

// MARK: - UIStackView

extension UIStackView {
    class func oba_horizontalStack(arrangedSubviews views: [UIView]) -> UIStackView {
        return oba_stack(axis: .horizontal, arrangedSubviews: views)
    }

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

protocol Autolayoutable {
    static func autolayoutNew() -> Self
}

extension UIView: Autolayoutable {
    static func autolayoutNew() -> Self {
        let view = self.init(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }
}

extension UIView {


    func embedInWrapperView(setConstraints: Bool = true) -> UIView {
        let wrapper = UIView(frame: .zero)
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(self)

        if setConstraints {
            pinEdgesToSuperview()
        }

        return wrapper
    }

    func pinEdgesToSuperview() {
        guard let superview = superview else {
            return
        }

        pinHorizontally(to: superview)
        pinVertically(to: superview)
    }

    func pinHorizontally(to view: UIView) {
        leadingAnchor.pin(to: view.safeAreaLayoutGuide.leadingAnchor)
        trailingAnchor.pin(to: view.safeAreaLayoutGuide.trailingAnchor)
    }

    func pinVertically(to view: UIView) {
        topAnchor.pin(to: view.safeAreaLayoutGuide.topAnchor)
        bottomAnchor.pin(to: view.safeAreaLayoutGuide.bottomAnchor)
    }
}
