//
//  StopArrivalView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 1/6/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import UIKit

/// This view displays the route, headsign, and predicted arrival/departure time for an `ArrivalDeparture`.
///
/// This view is what displays the core information at the heart of the `StopViewController`, and everywhere
/// else that we show information from an `ArrivalDeparture`.
@objc(OBAStopArrivalView)
public class StopArrivalView: UIView {

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

    let disclosureIndicator: UIImageView = {
        let view = UIImageView(image: Icons.chevron)
        view.contentMode = .center
        view.setContentHuggingPriority(.required, for: .horizontal)

        return view
    }()

    private var _formatters: Formatters!
    @objc dynamic var formatters: Formatters {
        get { return _formatters }
        set { _formatters = newValue }
    }

    @objc public var arrivalDeparture: ArrivalDeparture! {
        didSet {
            // 'Gray out' the view if it occurred in the past.
            alpha = arrivalDeparture.temporalState == .past ? 0.50 : 1.0

            routeHeadsignLabel.text = arrivalDeparture.routeAndHeadsign

            let arrDepTime = formatters.timeFormatter.string(from: arrivalDeparture.arrivalDepartureDate)
            let explanationText = formatters.formattedScheduleDeviation(for: arrivalDeparture)
            timeExplanationLabel.text = "\(arrDepTime) - \(explanationText)"

            minutesLabel.text = formatters.shortFormattedTime(until: arrivalDeparture)
            minutesLabel.textColor = formatters.colorForScheduleStatus(arrivalDeparture.scheduleStatus)
        }
    }

    @objc override init(frame: CGRect) {
        super.init(frame: frame)

        let leftStack = UIStackView.verticalStack(arangedSubviews: [routeHeadsignLabel, timeExplanationLabel])
        let leftStackWrapper = leftStack.embedInWrapperView()

        let minutesLabelWrapper = minutesLabel.embedInWrapperView(setConstraints: false)
        NSLayoutConstraint.activate([
            minutesLabel.trailingAnchor.constraint(equalTo: minutesLabelWrapper.trailingAnchor),
            minutesLabel.centerYAnchor.constraint(equalTo: minutesLabelWrapper.centerYAnchor),
            minutesLabelWrapper.widthAnchor.constraint(greaterThanOrEqualTo: minutesLabel.widthAnchor),
            minutesLabelWrapper.heightAnchor.constraint(greaterThanOrEqualTo: minutesLabel.heightAnchor)
        ])

        let outerStack = UIStackView.horizontalStack(arrangedSubviews: [leftStackWrapper, minutesLabelWrapper, disclosureIndicator])
        outerStack.spacing = ThemeMetrics.padding

        addSubview(outerStack)
        outerStack.pinToSuperview(.edges)

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
}
