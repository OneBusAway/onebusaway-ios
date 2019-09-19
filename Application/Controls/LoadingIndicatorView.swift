//
//  LoadingIndicatorView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 9/19/19.
//

import UIKit

/// An activity indicator and a label stacked together horizontally.
public class LoadingIndicatorView: UIView {
    private let activityIndicator: UIActivityIndicatorView
    private let label: UILabel

    init() {
        if #available(iOS 13.0, *) {
            activityIndicator = UIActivityIndicatorView(style: .medium)
        }
        else {
            activityIndicator = UIActivityIndicatorView(style: .gray)
        }

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false

        label = UILabel.autolayoutNew()
        label.text = Strings.loading

        super.init(frame: .zero)

        let stack = UIStackView.horizontalStack(arrangedSubviews: [activityIndicator, label])
        stack.spacing = ThemeMetrics.ultraCompactPadding
        addSubview(stack)
        stack.pinToSuperview(.edges)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func startAnimating() {
        activityIndicator.startAnimating()
    }

    func stopAnimating() {
        activityIndicator.stopAnimating()
    }

    var isAnimating: Bool { activityIndicator.isAnimating }
}
