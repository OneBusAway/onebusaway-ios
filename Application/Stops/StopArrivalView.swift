//
//  StopArrivalView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 1/6/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import UIKit
import AloeStackView

/// This view displays the route, headsign, and predicted arrival/departure time for an `ArrivalDeparture`.
///
/// This view is what displays the core information at the heart of the `StopViewController`, and everywhere
/// else that we show information from an `ArrivalDeparture`.
public class StopArrivalView: UIView, Highlightable {

    let kUseDebugColors = false

    /// First line in the view; contains route and headsign information.
    ///
    /// For example, this might contain the text `10 - Downtown Seattle`.
    let routeHeadsignLabel = buildLabel()

    /// Second line in the view; contains the arrival/departure time and status relative to schedule.
    ///
    /// For example, this might contain the text `11:20 AM - arriving on time`.
    let timeExplanationLabel = buildLabel()

    /// Appears on the trailing side of the view; contains the number of minutes until arrival/departure.
    ///
    /// For example, this might contain the text `10m`.
    let minutesLabel: HighlightChangeLabel = {
        let label = HighlightChangeLabel.autolayoutNew()
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)

        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)

        return label
    }()

    var showDisclosureIndicator: Bool = true {
        didSet {
            guard oldValue != showDisclosureIndicator else { return }

            if showDisclosureIndicator {
                outerStackView.addArrangedSubview(disclosureIndicator)
            }
            else {
                outerStackView.removeArrangedSubview(disclosureIndicator)
                disclosureIndicator.removeFromSuperview()
            }
        }
    }

    let disclosureIndicator: UIImageView = {
        let view = UIImageView(image: Icons.chevron)
        view.contentMode = .center
        view.setContentHuggingPriority(.required, for: .horizontal)

        return view
    }()

    /// The font used on the time explanation label.
    @objc public dynamic var timeExplanationFont: UIFont {
        set { _timeExplanationFont = newValue }
        get { return _timeExplanationFont }
    }
    private var _timeExplanationFont = UIFont.preferredFont(forTextStyle: .footnote)

    /// When `true`, decrease the `alpha` value of this cell if it happened in the past.
    public var deemphasizePastEvents = true

    public var formatters: Formatters!

    public var arrivalDeparture: ArrivalDeparture! {
        didSet {
            if deemphasizePastEvents {
                // 'Gray out' the view if it occurred in the past.
                alpha = arrivalDeparture.temporalState == .past ? 0.50 : 1.0
            }

            routeHeadsignLabel.text = arrivalDeparture.routeAndHeadsign

            let arrDepTime = formatters.timeFormatter.string(from: arrivalDeparture.arrivalDepartureDate)

            let explanationText: String
            if arrivalDeparture.scheduleStatus == .unknown {
                explanationText = Strings.scheduledNotRealTime
            }
            else {
                explanationText = formatters.formattedScheduleDeviation(for: arrivalDeparture)
            }

            let scheduleStatusColor = formatters.colorForScheduleStatus(arrivalDeparture.scheduleStatus)

            let attributedExplanation = NSMutableAttributedString(string: "\(arrDepTime) - ", attributes: [NSAttributedString.Key.font: timeExplanationFont])

            let explanation = NSAttributedString(string: explanationText, attributes: [NSAttributedString.Key.font: timeExplanationFont, NSAttributedString.Key.foregroundColor: scheduleStatusColor])
            attributedExplanation.append(explanation)

            timeExplanationLabel.attributedText = attributedExplanation

            minutesLabel.text = formatters.shortFormattedTime(until: arrivalDeparture)
            minutesLabel.textColor = scheduleStatusColor
        }
    }

    private lazy var minutesLabelWrapper: UIView = {
        let minutesLabelWrapper = minutesLabel.embedInWrapperView(setConstraints: false)
        NSLayoutConstraint.activate([
            minutesLabel.trailingAnchor.constraint(equalTo: minutesLabelWrapper.trailingAnchor),
            minutesLabel.centerYAnchor.constraint(equalTo: minutesLabelWrapper.centerYAnchor),
            minutesLabelWrapper.widthAnchor.constraint(greaterThanOrEqualTo: minutesLabel.widthAnchor),
            minutesLabelWrapper.heightAnchor.constraint(greaterThanOrEqualTo: minutesLabel.heightAnchor)
        ])
        return minutesLabelWrapper
    }()

    private lazy var leftStack: UIView = {
        let leftStack = UIStackView.verticalStack(arangedSubviews: [routeHeadsignLabel, timeExplanationLabel])
        return leftStack.embedInWrapperView()
    }()

    private lazy var outerStackView: UIStackView = {
        let outerStack = UIStackView.horizontalStack(arrangedSubviews: [leftStack, minutesLabelWrapper, disclosureIndicator])
        outerStack.spacing = ThemeMetrics.padding
        return outerStack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(outerStackView)
        outerStackView.pinToSuperview(.edges)

        if kUseDebugColors {
            routeHeadsignLabel.backgroundColor = .red
            timeExplanationLabel.backgroundColor = .orange
            disclosureIndicator.backgroundColor = .blue
            minutesLabel.backgroundColor = .purple
            minutesLabelWrapper.backgroundColor = .green
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private class func buildLabel() -> UILabel {
        let label = UILabel.autolayoutNew()
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }

    // MARK: - Highlightable

    public func setIsHighlighted(_ isHighlighted: Bool) {
      guard let cell = superview as? StackViewCell else { return }
        cell.backgroundColor = isHighlighted ? ThemeColors.shared.highlightedBackgroundColor : cell.rowBackgroundColor
    }
}
