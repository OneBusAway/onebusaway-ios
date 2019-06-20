//
//  TableHeaderView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 6/13/19.
//

import UIKit

/// A view that approximates the appearance of a UITableView section header.
///
/// - Note: Nominally, this is meant to be used in an `AloeStackView` or with `IGListKit`.
public class TableHeaderView: UIView {
    public let textLabel = UILabel.autolayoutNew()

    @objc public dynamic var font: UIFont {
        get { return textLabel.font }
        set { textLabel.font = newValue }
    }

    @objc public dynamic var textColor: UIColor {
        get { return textLabel.textColor }
        set { textLabel.textColor = newValue }
    }

    /// A convenience initializer for use with Auto Layout.
    ///
    /// - Parameter text: The text to display in this view's `textLabel`.
    public convenience init(text: String) {
        self.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        textLabel.text = text
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(textLabel)
        textLabel.pinToSuperview(.edges)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
