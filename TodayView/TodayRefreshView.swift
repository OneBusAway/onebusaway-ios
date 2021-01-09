//
//  TodayRefreshView.swift
//  OneBusAway Today
//
//  Created by Aaron Brethorst on 3/3/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import UIKit
import OBAKitCore

class TodayRefreshView: UIControl {

    // MARK: - UI Components

    private lazy var lastUpdatedLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        return label
    }()

    private lazy var refreshImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "arrow.clockwise"))
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private lazy var activityView: UIActivityIndicatorView = {
        let activity = UIActivityIndicatorView(style: .medium)
        activity.hidesWhenStopped = true
        return activity
    }()

    private lazy var refreshLabel: UILabel = {
        let label = UILabel()
        label.text = Strings.refresh
        label.font = .preferredFont(forTextStyle: .footnote)
        return label
    }()

    private lazy var stackView: UIStackView = {
        let spacer = UIView.init()
        let stack = UIStackView(arrangedSubviews: [lastUpdatedLabel, spacer, refreshImageView, activityView, refreshLabel])
        stack.spacing = ThemeMetrics.ultraCompactPadding
        stack.isUserInteractionEnabled = false
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
        refreshImageView.isHidden = true
        activityView.startAnimating()

        refreshLabel.text = Strings.updating
    }

    public func stopRefreshing() {
        activityView.stopAnimating()
        refreshImageView.isHidden = false
        refreshLabel.text = Strings.refresh
    }
}
