//
//  TableHeaderView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 6/13/19.
//

import UIKit

/// A view that approximates the appearance of a UITableView section header.
///
public class TableHeaderView: UIView {
    private let textLabel = UILabel.autolayoutNew()

    public var text: String? {
        get {
            textLabel.text
        }
        set {
            if let newValue = newValue {
                textLabel.text = newValue.uppercased()
                textLabel.accessibilityLabel = newValue
            }
            else {
                textLabel.text = nil
                textLabel.accessibilityLabel = nil
            }
        }
    }

    @objc public dynamic var font: UIFont {
        get { return textLabel.font }
        set { textLabel.font = newValue }
    }

    @objc public dynamic var textColor: UIColor {
        get { return textLabel.textColor }
        set { textLabel.textColor = newValue }
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(textLabel)
        NSLayoutConstraint.activate([
            textLabel.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            textLabel.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            textLabel.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            textLabel.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
