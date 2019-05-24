//
//  StopCell.swift
//  OBANext
//
//  Created by Aaron Brethorst on 12/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import UIKit

final class StopCell: SelfSizingCollectionCell {
    private static let nearbyInsets = UIEdgeInsets(top: 8, left: 15, bottom: 8, right: 15)
    private let highlightedBackgroundColor = UIColor(white: 0.9, alpha: 1.0)
    private let regularBackgroundColor = UIColor.clear

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.backgroundColor = .clear
        label.numberOfLines = 0
        label.font = UIFont.systemFont(ofSize: 17)
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.backgroundColor = .clear
        label.numberOfLines = 0
        label.font = UIFont.systemFont(ofSize: UIFont.smallSystemFontSize)
        return label
    }()

    var viewModel: StopViewModel? {
        didSet {
            guard let viewModel = viewModel else {
                return
            }

            titleLabel.text = viewModel.nameWithDirection

            let joinedRouteNames = viewModel.routeNames.joined(separator: ", ")
            let fmt = NSLocalizedString("nearby_stop_cell.routes_label_fmt", value: "Routes: %@", comment: "A format string used to denote the list of routes served by this stop. e.g. 'Routes: 10, 12, 49'")

            subtitleLabel.text = String(format: fmt, joinedRouteNames)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        subtitleLabel.text = nil
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.addSublayer(separator)

        let stack = UIStackView.verticalStack(arangedSubviews: [titleLabel, subtitleLabel])
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            contentView.layoutMarginsGuide.heightAnchor.constraint(greaterThanOrEqualTo: stack.heightAnchor),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44.0)
            ])
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            contentView.backgroundColor = isHighlighted ? highlightedBackgroundColor : regularBackgroundColor
        }
    }

    let separator: CALayer = {
        let layer = CALayer()
        layer.backgroundColor = UIColor(red: 200 / 255.0, green: 199 / 255.0, blue: 204 / 255.0, alpha: 1).cgColor
        return layer
    }()

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = contentView.bounds
        let height: CGFloat = 0.5
        let left = StopCell.nearbyInsets.left
        separator.frame = CGRect(x: left, y: bounds.height - height, width: bounds.width - left, height: height)
    }
}
