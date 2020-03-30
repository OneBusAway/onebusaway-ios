//
//  StopArrivalView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 1/6/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import UIKit
import AloeStackView
import OBAKitCore

// MARK: - StopArrivalDelegate

public protocol StopArrivalDelegate: NSObjectProtocol {
    func actionsButtonTapped(arrivalDeparture: ArrivalDeparture)
    func stopArrivalTapped(arrivalDeparture: ArrivalDeparture)
}

// MARK: - StopArrivalView

/// This view displays the route, headsign, and predicted arrival/departure time for an `ArrivalDeparture`.
///
/// This view is what displays the core information at the heart of the `StopViewController`, and everywhere
/// else that we show information from an `ArrivalDeparture`.
public class StopArrivalView: UIView, Highlightable, Tappable {

    public weak var delegate: StopArrivalDelegate?

    let kUseDebugColors = false

    // MARK: - Outer Stack

    private lazy var outerStackView: UIStackView = {
        let outerStack = UIStackView.horizontalStack(arrangedSubviews: [infoStackWrapper, minutesWrapper])
        outerStack.spacing = ThemeMetrics.compactPadding
        return outerStack
    }()

    // MARK: - Info Labels

    /// First line in the view; contains route and headsign information.
    ///
    /// For example, this might contain the text `10 - Downtown Seattle`.
    let routeHeadsignLabel: UILabel = {
        let label = buildLabel()
        label.numberOfLines = 0
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.font = UIFont(descriptor: .preferredFontDescriptor(withTextStyle: .headline), size: 16)
        return label
    }()

    /// Second line in the view; contains the arrival/departure time and status relative to schedule.
    ///
    /// For example, this might contain the text `11:20 AM - arriving on time`.
    let timeExplanationLabel = buildLabel()

    private lazy var infoStack: UIStackView = UIStackView.verticalStack(arrangedSubviews: [routeHeadsignLabel, timeExplanationLabel, UIView.autolayoutNew()])

    private lazy var infoStackWrapper = infoStack.embedInWrapperView()

    // MARK: - Minutes to Departure Labels

    /// Appears on the trailing side of the view; contains the number of minutes until arrival/departure.
    ///
    /// For example, this might contain the text `10m`.
    let minutesLabel = HighlightChangeLabel.autolayoutNew()

    lazy var minutesWrapper: UIView = {
        let wrapper = minutesLabel.embedInWrapperView(setConstraints: false)
        NSLayoutConstraint.activate([
            minutesLabel.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            minutesLabel.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            minutesLabel.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
            wrapper.heightAnchor.constraint(greaterThanOrEqualTo: minutesLabel.heightAnchor)
        ])
        return wrapper
    }()

    // MARK: - Actions/'...' Button

    var showActionsButton: Bool = false {
        didSet {
            guard oldValue != showActionsButton else { return }

            if showActionsButton {
                outerStackView.addArrangedSubview(actionsButton)
            }
            else {
                actionsButton.removeFromSuperview()
            }
        }
    }

    private lazy var actionsButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(Icons.showMore, for: .normal)
        button.addTarget(self, action: #selector(actionsButtonTapped), for: .touchUpInside)
        button.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 40.0)
        ])
        return button
    }()

    @objc private func actionsButtonTapped() {
        delegate?.actionsButtonTapped(arrivalDeparture: arrivalDeparture)
    }

    // MARK: - Public Properties

    /// When `true`, decrease the `alpha` value of this cell if it happened in the past.
    public var deemphasizePastEvents = true

    public var formatters: Formatters!

    // MARK: - Data Setters

    public func prepareForReuse() {
        routeHeadsignLabel.text = nil
        timeExplanationLabel.text = nil
        minutesLabel.text = ""
    }

    /// Set this to display data in this view.
    public var arrivalDeparture: ArrivalDeparture! {
        didSet {
            if deemphasizePastEvents {
                // 'Gray out' the view if it occurred in the past.
                alpha = arrivalDeparture.temporalState == .past ? 0.50 : 1.0
            }

            routeHeadsignLabel.text = arrivalDeparture.routeAndHeadsign
            timeExplanationLabel.attributedText = formatters.fullAttributedExplanation(from: arrivalDeparture)

            minutesLabel.text = formatters.shortFormattedTime(until: arrivalDeparture)
            minutesLabel.textColor = formatters.colorForScheduleStatus(arrivalDeparture.scheduleStatus)
        }
    }

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(outerStackView)
        outerStackView.pinToSuperview(.edges)

        if kUseDebugColors {
            routeHeadsignLabel.backgroundColor = .red
            timeExplanationLabel.backgroundColor = .orange
            minutesLabel.backgroundColor = .purple
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Highlightable

    public func setIsHighlighted(_ isHighlighted: Bool) {
        guard let cell = superview as? StackViewCell else { return }
        cell.backgroundColor = isHighlighted ? ThemeColors.shared.highlightedBackgroundColor : cell.rowBackgroundColor
    }

    // MARK: - Tappable

    public func didTapView() {
        delegate?.stopArrivalTapped(arrivalDeparture: arrivalDeparture)
    }

    // MARK: - UI Builders

    private class func buildLabel() -> UILabel {
        let label = UILabel.autolayoutNew()
        label.setHugging(horizontal: .defaultLow, vertical: .defaultLow)
        label.setCompressionResistance(horizontal: .required, vertical: .required)

        return label
    }

    private func buildMinutesLabelWrapper(label: UILabel) -> UIView {
        let wrapper = label.embedInWrapperView()
        wrapper.setCompressionResistance(horizontal: .required, vertical: .required)
        return wrapper
    }
}
