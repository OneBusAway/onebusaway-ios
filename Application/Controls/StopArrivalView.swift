//
//  StopArrivalView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 1/6/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import UIKit

@objc(OBAStopArrivalView)
public class StopArrivalView: UIView {

    let kUseDebugColors = false

    let routeHeadsignLabel = buildLabel()
    let timeLabel = buildLabel()

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
            routeHeadsignLabel.text = arrivalDeparture.routeAndHeadsign

            // 'Gray out' the view if it occurred in the past.
            alpha = arrivalDeparture.temporalStateOfArrivalDepartureDate == .past ? 0.50 : 1.0

            let timeText = formatters.timeFormatter.string(from: arrivalDeparture.arrivalDepartureDate)
            let explanationText = formatters.explanation(from: arrivalDeparture)
            timeLabel.text = "\(timeText) - \(explanationText)"
        }
    }

    @objc override init(frame: CGRect) {
        super.init(frame: frame)

        let leftStack = UIStackView.verticalStack(arangedSubviews: [routeHeadsignLabel, timeLabel])
        let leftStackWrapper = leftStack.embedInWrapperView()

        let outerStack = UIStackView.horizontalStack(arrangedSubviews: [leftStackWrapper, disclosureIndicator])

        addSubview(outerStack)
        outerStack.pinToSuperview(.edges)

        if kUseDebugColors {
            routeHeadsignLabel.backgroundColor = .red
            timeLabel.backgroundColor = .orange
            disclosureIndicator.backgroundColor = .blue
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
