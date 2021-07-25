//
//  TodayRefreshView.swift
//  OneBusAway Today
//
//  Created by Aaron Brethorst on 3/3/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import UIKit
import OBAKitCore

class TodayRefreshView: UIView {

    // MARK: - UI Components

    private lazy var lastUpdatedLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        return label
    }()

    lazy var refreshButton: UIButton = {
        let button = UIButton.autolayoutNew()
        button.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        button.setTitle(Strings.refresh, for: .normal)
        button.setTitle(Strings.updating, for: .disabled)
        button.backgroundColor = ThemeColors.shared.brand
        button.layer.cornerRadius = 4.0
        button.imageView?.contentMode = .scaleAspectFit
        button.setTitleColor(.lightText, for: .normal)
        button.tintColor = .lightText
        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: UIFont.TextStyle.footnote).bold
        button.contentEdgeInsets = UIEdgeInsets(top: 2, left: 4, bottom: 2, right: 4)
        button.isUserInteractionEnabled = true
        return button
    }()

    private lazy var stackView: UIStackView = {
        let spacer = UIView.init()
        let stack = UIStackView(arrangedSubviews: [lastUpdatedLabel, spacer, refreshButton])
        stack.spacing = ThemeMetrics.ultraCompactPadding
        stack.isUserInteractionEnabled = true
        NSLayoutConstraint.activate([
            stack.heightAnchor.constraint(greaterThanOrEqualToConstant: 20)
        ])

        return stack
    }()

    // MARK: - Last Updated At

    public var lastUpdatedAt: Date? {
        didSet {
            var formattedDate = OBALoc("refresh_cell.never_updated", value: "never", comment: "A string indicating that there is no data because we haven't downloaded it")

            defer {
                let formatString = OBALoc("refresh_cell.last_updated_format", value: "Last updated: %@", comment: "")
                lastUpdatedLabel.text = String.init(format: formatString, formattedDate)
            }

            guard let lastUpdatedAt = lastUpdatedAt else {
                return
            }

            if Calendar.current.isDateInToday(lastUpdatedAt) {
                formattedDate = todayFormatter.string(from: lastUpdatedAt)
            } else {
                formattedDate = anyDayFormatter.string(from: lastUpdatedAt)
            }
        }
    }

    private lazy var todayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private lazy var anyDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.lastUpdatedAt = nil

        self.addSubview(stackView)
        stackView.pinToSuperview(.edges)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - Refresh
extension TodayRefreshView {
    public func beginRefreshing() {
        refreshButton.isEnabled = false
    }

    public func stopRefreshing() {
        refreshButton.isEnabled = true
    }
}
