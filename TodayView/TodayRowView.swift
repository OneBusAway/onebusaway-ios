//
//  TodayRowView.swift
//  OneBusAway Today
//
//  Created by Aaron Brethorst on 3/1/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import UIKit
import OBAKitCore

enum TodayRowViewState {
    case loading
    case error
    case complete
}

class TodayRowView: UIView {
    // MARK: - State
    var formatters: Formatters
    var loadingState: TodayRowViewState = .loading

    var departures: [ArrivalDeparture]? {
        didSet {
            updateDepartures()
        }
    }

    public var bookmark: Bookmark? {
        didSet {
            titleLabel.text = bookmark?.name
        }
    }

    // MARK: - UI

    private lazy var hairline: UIView = {
        let view = UIView.autolayoutNew()
        view.backgroundColor = UIColor(white: 1.0, alpha: 0.25)

        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: 0.5)
        ])

        return view
    }()

    private lazy var outerStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [hairline, outerLabelStack])
        stack.axis = .vertical

        return stack
    }()

    private lazy var outerLabelStack: UIStackView = {
        let leftStackWrapper = titleLabelStack.embedInWrapperView()
        let departuresStackWrapper = departuresStack.embedInWrapperView()
        let stack = UIStackView(arrangedSubviews: [leftStackWrapper, departuresStackWrapper])
        stack.axis = .horizontal
        stack.spacing = ThemeMetrics.compactPadding

        return stack
    }()

    // MARK: - Title Info Labels
    private lazy var titleLabelStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [titleLabel, nextDepartureLabel])
        stack.axis = .vertical
        stack.spacing = ThemeMetrics.compactPadding

        return stack
    }()

    private lazy var titleLabel: UILabel = {
        let label = TodayRowView.buildInfoLabel(font: UIFont.preferredFont(forTextStyle: .footnote).bold)
        label.numberOfLines = 0
        return label
    }()

    private lazy var nextDepartureLabel: UILabel = {
        let label = TodayRowView.buildInfoLabel(font: .preferredFont(forTextStyle: .footnote))
        label.text = OBALoc("today_screen.tap_for_more_information", value: "Tap for more information", comment: "Tap for more information subheading on Today view")

        return label
    }()

    // MARK: - Departure Labels

    private let leadingDepartureLabel = TodayRowView.buildDepartureBadge()
    private let middleDepartureLabel = TodayRowView.buildDepartureBadge()
    private let trailingDepartureLabel = TodayRowView.buildDepartureBadge()

    private lazy var departuresStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [leadingDepartureLabel, middleDepartureLabel, trailingDepartureLabel])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = ThemeMetrics.compactPadding
        stack.isUserInteractionEnabled = false

        return stack
    }()

    // MARK: - Init

    init(frame: CGRect, formatters: Formatters) {
        self.formatters = formatters
        super.init(frame: frame)

        self.addSubview(outerStack)
        outerStack.pinToSuperview(.edges)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Private Helpers
    private static func buildInfoLabel(font: UIFont) -> UILabel {
        let label = UILabel.autolayoutNew()
        label.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)
        label.font = font
        label.minimumScaleFactor = 0.8
        return label
    }

    private static func buildDepartureBadge() -> DepartureTimeBadge {
        let badge = DepartureTimeBadge()
        badge.font = UIFont.preferredFont(forTextStyle: .footnote).bold
        NSLayoutConstraint.activate([
            badge.heightAnchor.constraint(equalToConstant: 24),
            badge.widthAnchor.constraint(equalToConstant: 42)
        ])

        return badge
    }

    // MARK: - Departures
    fileprivate func updateDepartures() {
        let formatString = OBALoc("today_view.no_departures_in_next_n_minutes_fmt", value: "No departures in the next %@ minutes", comment: "")
        let nextDepartureText = String(format: formatString, String(kMinutes))
        nextDepartureLabel.text = nextDepartureText

        applyUpcomingDeparture(at: 0, to: leadingDepartureLabel)
        applyUpcomingDeparture(at: 1, to: middleDepartureLabel)
        applyUpcomingDeparture(at: 2, to: trailingDepartureLabel)

        guard let firstDeparture = departures?.first else {
            return
        }

        nextDepartureLabel.text = formatters.formattedScheduleDeviation(for: firstDeparture)
    }

    private func applyUpcomingDeparture(at index: Int, to badge: DepartureTimeBadge) {
        if let departures = departures, index < departures.count {
            badge.isHidden = false
            badge.configure(with: departures[index], formatters: formatters)
        } else {
            badge.isHidden = true
        }
    }
}
